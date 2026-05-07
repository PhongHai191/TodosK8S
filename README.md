# TodosK8S K8s Local

Full-stack Todo app deployed on a self-managed Kubernetes cluster with AWS-managed backing services (RDS, Redis, S3, ECR). CI/CD runs on a self-hosted GitHub Actions runner in WSL2.

## Infrastructure

| Component | Details |
|---|---|
| k8s-master | 192.168.241.10 — control plane, ingress-nginx |
| k8s-worker-1 | 192.168.241.11 — app workloads (frontend + backend) |
| k8s-worker-2 | 192.168.241.12 — monitoring + logging |
| Network | Calico CNI (Pod: 10.244.0.0/16, Svc: 10.96.0.0/12) |
| AWS region | ap-southeast-2 |

## Quick Access

| Service | URL |
|---|---|
| App | `http://192.168.241.10:30080` |
| Grafana | `http://192.168.241.10:30000` (admin / admin123) |

## Prerequisites

Before the first deploy, you need:

1. **K8s cluster running** — 3 nodes joined, all `Ready`
2. **ingress-nginx installed** on the cluster
3. **Terraform applied** — RDS, Redis, S3, ECR, IAM provisioned
4. **`k8s/todoapp/secret.yaml` filled** with real credentials (gitignored)
5. **Self-hosted runner configured** in WSL2 (see [DEPLOY.md](DEPLOY.md))

## Deploy

Push to `main` — the pipeline handles everything:

```bash
git add .
git commit -m "feat: ..."
git push origin main
```

Pipeline: `ci` → `build` (ECR push) → `deploy` (rsync + Ansible + rolling update)

## Manual Operations

```bash
# View app logs (from master VM)
kubectl logs -n todoapp deployment/backend  --tail=100 -f
kubectl logs -n todoapp deployment/frontend --tail=100 -f

# Rollback
kubectl rollout undo deployment/backend  -n todoapp
kubectl rollout undo deployment/frontend -n todoapp

# Scale
kubectl scale deployment backend  --replicas=3 -n todoapp

# Refresh ECR imagePullSecret (token expires every 12h)
cd ansible
AWS_ACCOUNT_ID=529646246979 AWS_REGION=ap-southeast-2 \
  ansible-playbook -i inventories/dev playbooks/site.yml

# Update credentials (after editing secret.yaml on master VM)
kubectl apply -f /home/ubuntu/k8s/todoapp/secret.yaml
kubectl rollout restart deployment/backend deployment/frontend -n todoapp

# Re-init DB schema
ansible-playbook -i inventories/dev playbooks/db.yml --tags init
```

## Troubleshooting

| Symptom | Check |
|---|---|
| `ImagePullBackOff` | ECR token expired — re-run `site.yml` or push a new commit |
| Pods `Pending` | `kubectl get nodes` — node name must match `nodeSelector` in manifests |
| `CrashLoopBackOff` | `kubectl logs -n todoapp deployment/backend` |
| Health check fail in pipeline | `kubectl get events -n todoapp --sort-by='.lastTimestamp'` |
| Ansible SSH fail | `ssh -i ~/.ssh/k8s_master -v ubuntu@192.168.241.10` |
| Ingress 404 | `kubectl describe ingress todoapp-ingress -n todoapp` |
| `ingress-nginx` not routing | `kubectl get svc -n ingress-nginx` — check NodePort is 30080 |

## Structure

```
k8s/          Kubernetes manifests
ansible/      Playbooks: site.yml (bootstrap), web.yml (deploy), db.yml (DB init)
terraform/    AWS infrastructure (RDS, Redis, S3, ECR, IAM)
backend/      Node.js 18 + Express API
frontend/     NGINX + static HTML/CSS/JS
database/     init.sql schema
```

See [CLAUDE.md](CLAUDE.md) for full architecture and design decisions.
See [DEPLOY.md](DEPLOY.md) for first-time setup walkthrough.
