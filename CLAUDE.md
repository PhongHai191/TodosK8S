# AWStodo — Project Documentation

## Overview

Full-stack Todo web application deployed on AWS. Infrastructure managed by Terraform, configuration managed by Ansible, and delivery automated via GitHub Actions CI/CD with Docker containers.

## Architecture

```
Internet
  └── WAF (AWS WAFv2)
        └── ALB (Application Load Balancer)
              ├── port 80  → nginx container  (frontend)
              └── port 3000 → backend container (Node.js API)

Private App Subnet
  ├── EC2 web-1 (t3.small) — Docker: nginx + backend
  └── EC2 web-2 (t3.small) — Docker: nginx + backend

Private DB Subnet
  ├── RDS PostgreSQL 17 (db.t4g.micro)
  └── ElastiCache Redis 7.1 (cache.t3.micro)

Public Subnet
  ├── Bastion host (t3.micro) — SSH restricted to trusted IP
  └── NAT Gateway — outbound internet for private subnets

S3 bucket — avatars/ + deploy/ + ansible-tmp/
ECR         — awstodo-backend, awstodo-nginx
Secrets Manager — SSH keys, DB credentials (KMS encrypted)
SSM Param Store — /todoapp/* (runtime env vars for Docker)
```

## Tech Stack

| Layer | Technology |
|---|---|
| Frontend | Static HTML/CSS/JS served via NGINX |
| Backend | Node.js 18 + Express, port 3000 |
| Database | PostgreSQL 17 (RDS) |
| Cache | Redis 7.1 (ElastiCache) |
| Container | Docker + Docker Compose v2 |
| Container Registry | AWS ECR |
| Infrastructure | Terraform >= 1.10 |
| Configuration | Ansible + SSM Session Manager |
| CI/CD | GitHub Actions (OIDC — no long-lived keys) |
| AWS Region | ap-southeast-2 (Sydney) |

## Repository Structure

```
AWSTask/
├── backend/            Node.js Express API
│   ├── src/
│   │   ├── server.js
│   │   ├── db.js           PostgreSQL via pg
│   │   ├── redis.js        Redis client
│   │   ├── routes/         auth, todos, profile, health
│   │   ├── middleware/     JWT auth, no-cache headers
│   │   └── utils/          S3 (avatars), Secrets Manager
│   └── Dockerfile
├── frontend/           NGINX static + reverse proxy
│   ├── nginx.conf      /api/* and /health/* → backend:3000
│   ├── *.html
│   └── Dockerfile
├── database/
│   ├── init.sql
│   └── global-bundle.pem  RDS SSL cert
├── docker-compose.yml  Pulls images from ECR using $TAG
├── ansible/            Configuration management (see below)
├── terraform/          Infrastructure as Code (see below)
└── .github/workflows/
    └── cicd.yml        CI/CD pipeline
```

## Terraform Modules

Located in `terraform/modules/`, called from `terraform/environments/{dev,staging,production}/`.

| Module | Purpose |
|---|---|
| `network` | VPC, 3-tier subnets (public/private-app/private-db), IGW, NAT, route tables |
| `security-groups` | SGs for ALB, web, bastion, Redis, RDS |
| `kms` | Two KMS keys: RDS encryption, Secrets Manager encryption |
| `iam` | EC2 instance role + GitHub Actions OIDC role |
| `ec2` | Bastion + 2 web servers; SSH keys generated and stored in Secrets Manager |
| `alb` | ALB with two target groups: frontend (80), backend (3000); path-based routing /api/* → backend |
| `waf` | WAFv2 with rate limiting (2000 req/IP), SQLi protection, common rules |
| `rds` | PostgreSQL 17, Multi-AZ off, storage autoscaling 20-100GB, enhanced monitoring |
| `redis` | ElastiCache Redis 7.1, cache.t3.micro, daily snapshots |
| `s3` | Versioned bucket with lifecycle (90-day), avatars/ and deploy/ prefixes |

### Backend state bucket (bootstrap first)
```bash
cd terraform/bootstrap
terraform init && terraform apply
```

### Deploy per environment
```bash
cd terraform/environments/dev
terraform init && terraform apply
```

### Terraform backend (S3 native locking — Terraform >= 1.10)
```hcl
backend "s3" {
  bucket       = "awstodo-terraform-state-529646246979"
  key          = "dev/terraform.tfstate"
  region       = "ap-southeast-2"
  use_lockfile = true
  encrypt      = true
}
```

## Ansible Structure

```
ansible/
├── inventories/
│   ├── dev/aws_ec2.yml       Dynamic inventory — filters tag:Environment=dev
│   ├── staging/aws_ec2.yml
│   └── prod/aws_ec2.yml
├── roles/
│   ├── common/               OS updates, timezone, system limits
│   ├── docker/               Docker + Docker Compose v2 install (idempotent)
│   ├── nginx/                Verify nginx container health
│   └── app/                  ECR login, docker compose pull + up, .env from SSM
├── playbooks/
│   ├── site.yml              Full provision: common + docker
│   ├── web.yml               Deploy release: app + nginx health check
│   └── db.yml                DB connectivity check from web servers
├── group_vars/
│   └── webservers.yml        SSM Session Manager connection config
├── host_vars/
├── ansible.cfg
└── requirements.yml          amazon.aws, community.aws, community.docker
```

### Connection method: SSM Session Manager
Web servers are in private subnets with no public IPs. Ansible connects via AWS SSM Session Manager — no SSH keys or bastion needed from CI.

```yaml
# group_vars/webservers.yml
ansible_connection: community.aws.aws_ssm
ansible_aws_ssm_region: "ap-southeast-2"
ansible_aws_ssm_bucket_name: "{{ lookup('env', 'S3_BUCKET') }}"
ansible_aws_ssm_bucket_prefix: "ansible-tmp"
```

### Run locally
```bash
cd ansible
pip install ansible boto3 botocore
ansible-galaxy collection install -r requirements.yml

# Provision new instance
ansible-playbook -i inventories/dev playbooks/site.yml

# Deploy a release
IMAGE_TAG=<sha> AWS_ACCOUNT_ID=529646246979 S3_BUCKET=<bucket> \
  ansible-playbook -i inventories/dev playbooks/web.yml

# Check DB connectivity
ansible-playbook -i inventories/dev playbooks/db.yml
```

## CI/CD Pipeline

File: `.github/workflows/cicd.yml`

### Triggers
- Push to `main` branch

### CI job
1. Validate directory structure (backend/, frontend/, docker-compose.yml)
2. `npm ci` for backend dependencies

### CD job (requires CI)
1. AWS OIDC authentication (no stored AWS keys)
2. Build + push Docker images to ECR (tagged with `github.sha`)
3. Upload `docker-compose.yml` to S3 (versioned + latest)
4. Capture current running tag for rollback
5. Install `session-manager-plugin` + Ansible
6. **`site.yml`** — idempotent Docker setup on web servers
7. **`web.yml`** — deploy new images via Ansible
8. Health check via ALB DNS (`/health` + `/health/db`)
9. Auto-rollback to previous tag via Ansible if health check fails

### GitHub Secrets required
| Secret | Value |
|---|---|
| `AWS_ACCOUNT_ID` | `529646246979` |
| `AWS_REGION` | `ap-southeast-2` |
| `S3_BUCKET` | App S3 bucket name |
| `WEBSERVER1ID` | EC2 instance ID of web-1 (for rollback tag capture) |
| `LB_DNS` | ALB DNS name for health checks |

## IAM Roles

### EC2 instance role (`awstodo-dev-ec2-role`)
Permissions: SSM Session Manager, CloudWatch agent, ECR read, S3 (avatars/ deploy/ ansible-tmp/), Secrets Manager read, SSM Parameter Store read

### GitHub Actions OIDC role (`awstodo-dev-github-actions-role`)
Scoped to: `repo:PhongHai191/AWStodo:ref:refs/heads/main`
Permissions: ECR push, S3 deploy + ansible-tmp, SSM SendCommand + StartSession, EC2 DescribeInstances, Secrets Manager read, SSM Parameter Store read

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

## Environment Variables (SSM Parameter Store `/todoapp/`)

| Key | Description |
|---|---|
| `DB_HOST` | RDS endpoint |
| `DB_USER` | DB username |
| `DB_PASS` | DB password |
| `DB_NAME` | Database name |
| `REDIS_HOST` | ElastiCache endpoint |
| `JWT_ACCESS_SECRET` | JWT signing secret |
| `JWT_REFRESH_SECRET` | JWT refresh secret |
| `ACCESS_EXPIRE` | Access token TTL (e.g. `15m`) |
| `REFRESH_EXPIRE` | Refresh token TTL (e.g. `7d`) |
| `AWS_REGION` | AWS region |
| `AWS_S3_BUCKET` | S3 bucket for avatars |

## Key Decisions

- **SSM Session Manager** over SSH for Ansible: web servers have no public IPs; each has a different SSH key; GitHub Actions runners have dynamic IPs blocked by bastion SG
- **OIDC** for GitHub Actions: no long-lived AWS credentials stored in GitHub Secrets
- **`use_lockfile = true`** replaces DynamoDB for Terraform state locking (Terraform 1.10+)
- **IMDSv2 enforced** on all EC2 instances
- **Separate KMS keys** for RDS and Secrets Manager
- **Per-environment Terraform state** (`dev/`, `staging/`, `production/` keys in S3)
