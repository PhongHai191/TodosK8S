# TodosK8S K8s Local — Project Documentation

## Overview

Full-stack Todo web application running on a self-managed Kubernetes cluster (3 VMs) with AWS-managed backing services. CI/CD is fully automated via GitHub Actions with a self-hosted runner in WSL2.

## Architecture

```
Internet
  └── ingress-nginx (NodePort 30080/30443)
        └── k8s-master: 192.168.241.10
              ├── /api/*   → backend-svc:3000  (namespace: todoapp)
              ├── /health  → backend-svc:3000
              └── /        → frontend-svc:80   (namespace: todoapp)

k8s-worker-1: 192.168.241.11  (namespace: todoapp)
  ├── frontend pods x2  — nginx:80  (static HTML + /api/* proxy)
  └── backend pods x2   — Node.js:3000

k8s-worker-2: 192.168.241.12  (namespaces: monitoring, logging)
  ├── Prometheus :9090   — scrapes nodes, pods, kube-state-metrics, backend /metrics
  ├── Grafana    :3000   — NodePort 30000, datasources: Prometheus + Loki
  ├── node-exporter :9100  — DaemonSet on all nodes
  ├── kube-state-metrics :8080
  └── Loki :3100 / Promtail (DaemonSet on all nodes)

Network: Calico CNI
  Pod CIDR:  10.244.0.0/16
  Svc CIDR:  10.96.0.0/12

AWS (ap-southeast-2) — backing services only
  ├── ECR    — todosk8s-backend, todosk8s-nginx
  ├── RDS    — PostgreSQL 17 (TCP 5432)
  ├── ElastiCache — Redis 7.1 (TCP 6379)
  ├── S3     — avatars/
  ├── IAM    — GitHub Actions OIDC role
  └── Secrets Manager / SSM — credentials (accessed at deploy time, not runtime)
```

## Tech Stack

| Layer | Technology |
|---|---|
| Frontend | Static HTML/CSS/JS served via NGINX |
| Backend | Node.js 18 + Express, port 3000 |
| Database | PostgreSQL 17 (RDS, ap-southeast-2) |
| Cache | Redis 7.1 (ElastiCache) |
| Container | Docker |
| Container Registry | AWS ECR |
| Orchestration | Kubernetes (kubeadm), Calico CNI |
| Ingress | ingress-nginx (baremetal NodePort) |
| Monitoring | Prometheus + Grafana + node-exporter + kube-state-metrics |
| Logging | Loki + Promtail (DaemonSet) |
| Infrastructure | Terraform >= 1.10 (AWS services only) |
| Configuration | Ansible (SSH → master → kubectl) |
| CI/CD | GitHub Actions — self-hosted runner in WSL2 |
| AWS Region | ap-southeast-2 (Sydney) |

## Repository Structure

```
TodoK8s/
├── backend/                Node.js Express API
│   ├── src/
│   │   ├── server.js
│   │   ├── db.js           PostgreSQL via pg
│   │   ├── redis.js        Redis client
│   │   ├── routes/         auth, todos, profile, health, metrics
│   │   ├── middleware/     JWT auth, httpLogger, metrics, no-cache
│   │   └── utils/          S3 (avatars), Secrets Manager, logger
│   └── Dockerfile
├── frontend/               NGINX static + reverse proxy
│   ├── nginx.conf          /api/* and /health → backend-svc:3000
│   ├── *.html
│   └── Dockerfile
├── database/
│   └── init.sql
├── k8s/                    Kubernetes manifests
│   ├── namespaces.yaml     todoapp, monitoring, logging
│   ├── ingress/
│   │   └── ingress.yaml
│   ├── todoapp/
│   │   ├── backend.yaml    Deployment + Service (ClusterIP:3000)
│   │   ├── frontend.yaml   Deployment + Service (ClusterIP:80) + nginx ConfigMap
│   │   ├── configmap.yaml  NODE_ENV=production
│   │   └── secret.yaml     DB/Redis/JWT/S3 credentials (gitignored)
│   ├── monitoring/
│   │   ├── prometheus.yaml  Deployment + RBAC + ConfigMap
│   │   ├── grafana.yaml     Deployment + NodePort 30000
│   │   ├── node-exporter.yaml  DaemonSet
│   │   └── kube-state-metrics.yaml
│   └── logging/
│       ├── loki.yaml        Deployment
│       └── promtail.yaml    DaemonSet + RBAC
├── ansible/
│   ├── inventories/dev/hosts.yml   master: 192.168.241.10
│   ├── playbooks/
│   │   ├── site.yml        Bootstrap: preflight, namespaces, ECR secret, manifests, DB init
│   │   ├── web.yml         Deploy: ECR secret refresh, rolling update, health check, rollback
│   │   └── db.yml          DB connectivity check + schema init
│   ├── roles/
│   │   ├── k8s_deploy/     Rolling update logic with capture/rollback
│   │   └── db_init/        Init SQL execution
│   └── ansible.cfg
├── terraform/
│   ├── backend-bucket/     S3 state bucket (bootstrap once)
│   ├── environments/dev/   Main environment (RDS, Redis, S3, ECR, IAM)
│   └── modules/            alb, cloudwatch, ec2, iam, kms, network,
│                           rds, redis, s3, security-groups, ssm, waf
├── docker-compose.yml      Local dev only
└── .github/workflows/
    └── cicd.yml            CI/CD pipeline (self-hosted runner)
```

## Kubernetes Manifests

### Namespaces
| Namespace | Workloads |
|---|---|
| `todoapp` | frontend (x2), backend (x2) |
| `monitoring` | prometheus, grafana, node-exporter (DS), kube-state-metrics |
| `logging` | loki, promtail (DS) |

### Node placement (`nodeSelector: kubernetes.io/hostname`)
| Workload | Node |
|---|---|
| frontend, backend | `k8s-worker-1` |
| prometheus, grafana, loki | `k8s-worker-2` |
| node-exporter, promtail | all nodes (DaemonSet + `tolerations: Exists`) |

### Ingress routing (ingress-nginx, no host rule)
| Path | Backend |
|---|---|
| `/api` | backend-svc:3000 |
| `/health` | backend-svc:3000 |
| `/metrics` | backend-svc:3000 |
| `/` | frontend-svc:80 |

### NodePorts exposed
| Service | NodePort | Access URL |
|---|---|---|
| ingress-nginx | 30080 (HTTP) / 30443 (HTTPS) | `http://<any-node-ip>:30080` |
| grafana | 30000 | `http://<any-node-ip>:30000` |

## Ansible

### Connection method
Ansible runs on the self-hosted runner (WSL2), SSHes into master (`192.168.241.10`), then runs `kubectl` commands. No direct connection to workers needed.

```yaml
# ansible/inventories/dev/hosts.yml
master:
  ansible_host: 192.168.241.10
  ansible_user: ubuntu
  ansible_ssh_private_key_file: ~/.ssh/k8s_master
```

### Playbooks
| Playbook | Purpose |
|---|---|
| `site.yml` | Bootstrap (idempotent): preflight checks, namespaces, ECR secret, configmap, secret (first deploy only), all manifests, DB init |
| `web.yml` | Deploy: ECR secret refresh → rolling update → wait rollout → health check → auto-rollback on failure |
| `db.yml` | DB connectivity check + `init.sql` execution |

### Run locally
```bash
cd ansible

# Bootstrap (first deploy or re-verify)
AWS_ACCOUNT_ID=529646246979 AWS_REGION=ap-southeast-2 \
  ansible-playbook -i inventories/dev playbooks/site.yml

# Deploy new image
IMAGE_TAG=<sha> AWS_ACCOUNT_ID=529646246979 AWS_REGION=ap-southeast-2 \
  ansible-playbook -i inventories/dev playbooks/web.yml

# DB check / init
ansible-playbook -i inventories/dev playbooks/db.yml --tags init
```

## CI/CD Pipeline

File: [.github/workflows/cicd.yml](.github/workflows/cicd.yml)

All three jobs run on `self-hosted` (WSL2 Ubuntu on Windows host).

### Trigger
Push to `main` branch.

### Jobs
```
ci → build → deploy
```

**ci**
1. Validate `backend/`, `frontend/`, `k8s/` directories exist
2. Node.js 20 + `npm ci`

**build** (needs: ci)
1. AWS OIDC authentication
2. `docker build` + push backend image to ECR (tag: `github.sha` + `latest`)
3. `docker build` + push frontend image to ECR (tag: `github.sha` + `latest`)

**deploy** (needs: build)
1. AWS OIDC authentication
2. `rsync k8s/ → ubuntu@192.168.241.10:/home/ubuntu/k8s/`
3. `ansible-playbook site.yml` — bootstrap/preflight
4. `ansible-playbook web.yml` — rolling update with `IMAGE_TAG=${{ github.sha }}`
5. Health check `/health/db` via ingress ClusterIP (inside the Ansible role)
6. Auto-rollback to previous image tag if health check fails

### GitHub Secrets required
| Secret | Value |
|---|---|
| `AWS_ACCOUNT_ID` | `529646246979` |
| `AWS_REGION` | `ap-southeast-2` |

### Self-hosted runner requirements (WSL2)
- `ansible`, `boto3`, `amazon.aws` collection
- `rsync`
- `aws` CLI (for OIDC + ECR token)
- SSH key `~/.ssh/k8s_master` with access to `ubuntu@192.168.241.10`
- Docker (for image builds)

## Terraform

Manages AWS-only resources. K8s cluster itself is provisioned manually with kubeadm.

### Bootstrap (once)
```bash
cd terraform/backend-bucket
terraform init && terraform apply
```

### Dev environment
```bash
cd terraform/environments/dev
terraform init && terraform apply
```

### State backend
```hcl
backend "s3" {
  bucket       = "todosk8s-terraform-state-529646246979"
  key          = "dev/terraform.tfstate"
  region       = "ap-southeast-2"
  use_lockfile = true   # Terraform >= 1.10, no DynamoDB needed
  encrypt      = true
}
```

### Modules
| Module | Purpose |
|---|---|
| `network` | VPC, subnets, IGW, NAT |
| `security-groups` | SGs for ALB, web, bastion, RDS, Redis |
| `kms` | RDS + Secrets Manager encryption keys |
| `iam` | GitHub Actions OIDC role |
| `rds` | PostgreSQL 17 |
| `redis` | ElastiCache Redis 7.1 |
| `s3` | Avatars bucket |
| `ssm` | SSM Parameter Store entries |
| `waf` | WAFv2 rate limiting, SQLi, common rules |

## IAM Roles

### GitHub Actions OIDC role (`todosk8s-dev-github-actions-role`)
Scoped to: `repo:PhongHai191/TodosK8S:ref:refs/heads/main`
Permissions: ECR push, S3 read, SSM read, Secrets Manager read

## API Routes

| Method | Path | Description |
|---|---|---|
| POST | `/api/auth/register` | Register new user |
| POST | `/api/auth/login` | Login, returns JWT |
| POST | `/api/auth/refresh` | Refresh access token |
| POST | `/api/auth/logout` | Logout |
| GET/POST | `/api/todos` | List / create todos |
| PUT/DELETE | `/api/todos/:id` | Update / delete todo |
| GET/PUT | `/api/profile` | Get / update profile |
| POST | `/api/profile/avatar` | Upload avatar to S3 |
| GET | `/health` | Liveness check |
| GET | `/health/db` | Readiness check (DB + Redis) |
| GET | `/metrics` | Prometheus metrics |

## K8s Secret (`k8s/todoapp/secret.yaml`)

File is gitignored. Fill in before first deploy:

| Key | Description |
|---|---|
| `DB_HOST` | RDS endpoint |
| `DB_USER` | DB username |
| `DB_PASS` | DB password |
| `DB_NAME` | Database name |
| `DB_SSL` | `"true"` |
| `REDIS_HOST` | ElastiCache endpoint |
| `JWT_ACCESS_SECRET` | JWT signing secret |
| `JWT_REFRESH_SECRET` | JWT refresh secret |
| `AWS_REGION` | `ap-southeast-2` |
| `AWS_S3_BUCKET` | S3 bucket name |

## Key Decisions

- **Self-hosted runner in WSL2**: Ansible doesn't run natively on Windows; WSL2 provides a Linux environment on the Windows dev machine
- **Ansible SSHes to master only**: Workers are accessed exclusively via `kubectl` from master — no direct SSH to workers needed from CI
- **ECR secret refreshed every deploy**: ECR tokens expire after 12h; `site.yml` and `web.yml` both refresh `ecr-secret` at the start
- **Secret applied first-deploy-only**: `site.yml` skips `kubectl apply` for `todoapp-secret` if it already exists, preventing accidental overwrites
- **Rollback captures previous image tag**: `k8s_deploy` role stores the running image tag before update, rolls back to it if health check fails
- **OIDC for GitHub Actions**: No long-lived AWS credentials in GitHub Secrets
- **`use_lockfile = true`**: Replaces DynamoDB for Terraform state locking (Terraform 1.10+)
- **Calico CNI**: Pod CIDR 10.244.0.0/16, Svc CIDR 10.96.0.0/12
- **nodeSelector by hostname**: Each workload pinned to the correct node; node names must match `k8s-worker-1` / `k8s-worker-2` exactly
