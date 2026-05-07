# AWStodo K8s Local — Hướng dẫn Deploy

## Tổng quan luồng

```
push to main
  │
  ├── ci     (ubuntu-latest) — validate structure + npm ci
  ├── build  (ubuntu-latest) — docker build + push → ECR
  └── deploy (self-hosted — Windows host)
              │
              ├── rsync k8s/ → master VM
              ├── ansible site.yml  ← Bootstrap (idempotent)
              │     ├── preflight: nodes ready, ingress-nginx running
              │     ├── apply namespaces
              │     ├── refresh ECR imagePullSecret
              │     ├── apply configmap + secret (skip nếu secret đã có)
              │     ├── apply backend/frontend/ingress/monitoring/logging manifests
              │     └── db init schema (skip nếu tables đã tồn tại)
              └── ansible web.yml   ← Deploy
                    ├── refresh ECR imagePullSecret
                    ├── first deploy: kubectl apply (nếu deployment chưa có)
                    ├── rolling update: kubectl set image (nếu deployment đã có)
                    ├── wait rollout
                    ├── health check /health/db
                    └── rollback tự động nếu fail
```

Pipeline **idempotent hoàn toàn** — lần đầu hay lần thứ N đều chạy cùng một pipeline, không cần làm gì thủ công trên VM.

---

## Yêu cầu trước khi push lần đầu

### 1. Cluster K8s đã ready

SSH vào master, verify:
```bash
ssh ubuntu@192.168.241.10
kubectl get nodes -o wide
```

Expected:
```
NAME           STATUS   ROLES           INTERNAL-IP
k8s-master     Ready    control-plane   192.168.241.10
k8s-worker-1   Ready    <none>          192.168.241.11
k8s-worker-2   Ready    <none>          192.168.241.12
```

> **Quan trọng:** Tên node phải khớp với `nodeSelector` trong manifests.
> Kiểm tra: `kubectl get nodes --no-headers -o custom-columns=NAME:.metadata.name`
> Nếu tên khác, sửa `nodeSelector` trong [k8s/todoapp/backend.yaml](k8s/todoapp/backend.yaml),
> [k8s/todoapp/frontend.yaml](k8s/todoapp/frontend.yaml), và các file monitoring.

### 2. ingress-nginx đã cài

```bash
# Trên master VM
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.10.1/deploy/static/provider/baremetal/deploy.yaml
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=120s
```

### 3. Terraform đã apply (RDS + Redis + S3 + IAM)

```bash
# Từ Windows host hoặc bất kỳ máy nào có Terraform + AWS CLI
cd terraform/bootstrap && terraform init && terraform apply
cd terraform/environments/dev && terraform init && terraform apply

# Lấy outputs cần thiết
terraform output redis_endpoint
terraform output -raw rds_endpoint
terraform output s3_bucket_name
```

### 4. Điền credentials vào k8s/todoapp/secret.yaml

Mở [k8s/todoapp/secret.yaml](k8s/todoapp/secret.yaml), thay các `REPLACE_WITH_*`:

```yaml
DB_HOST:           "<rds-endpoint>"
DB_USER:           "postgres"
DB_PASS:           "<db_password>"
DB_NAME:           "postgres"
DB_SSL:            "true"
REDIS_HOST:        "<elasticache-endpoint>"
JWT_ACCESS_SECRET: "<random string>"
JWT_REFRESH_SECRET: "<random string>"
AWS_S3_BUCKET:     "<s3_bucket_name>"
```

> File này đã có trong `.gitignore` sau khi điền — không commit giá trị thật lên git.

### 5. Cài self-hosted runner trong WSL2

> Ansible không chạy được trên Windows native. Runner phải chạy trong WSL2 Ubuntu.

**5.1 — Cài WSL2**

Mở PowerShell (Administrator):
```powershell
wsl --install
# Reboot máy sau khi xong
```

Sau reboot, mở **Ubuntu** từ Start Menu → tạo username/password cho WSL2.

**5.2 — Cài Ansible + dependencies trong WSL2**

```bash
sudo apt update && sudo apt install -y python3-pip python3-boto3 rsync
pip3 install ansible
ansible-galaxy collection install amazon.aws

# Verify
ansible --version
```

**5.3 — Tạo SSH key và copy lên master VM**

```bash
# Trong WSL2 terminal
ssh-keygen -t ed25519 -f ~/.ssh/k8s_master -N ""
ssh-copy-id -i ~/.ssh/k8s_master.pub ubuntu@192.168.241.10

# Test
ssh -i ~/.ssh/k8s_master ubuntu@192.168.241.10 "kubectl get nodes"
```

**5.4 — Cài AWS CLI trong WSL2**

```bash
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip /tmp/awscliv2.zip -d /tmp
sudo /tmp/aws/install
aws --version
```

**5.5 — Đăng ký GitHub Actions runner trong WSL2**

Vào repo GitHub → **Settings** → **Actions** → **Runners** → **New self-hosted runner** → chọn **Linux / x64** → chạy các lệnh hiện ra trong WSL2:

```bash
mkdir ~/actions-runner && cd ~/actions-runner

# Download (URL + token lấy từ GitHub UI)
curl -o actions-runner-linux-x64.tar.gz -L \
  https://github.com/actions/runner/releases/download/v2.317.0/actions-runner-linux-x64-2.317.0.tar.gz
tar xzf actions-runner-linux-x64.tar.gz

# Config với token từ GitHub UI (hết hạn sau 1 tiếng)
./config.sh --url https://github.com/PhongHai191/AWStodo --token <TOKEN>

# Chạy như service (tự start khi Windows boot)
sudo ./svc.sh install
sudo ./svc.sh start
sudo ./svc.sh status
```

> Verify trên GitHub UI: runner hiện **Idle** là OK.

**5.4 — GitHub Secrets**

Vào repo → **Settings** → **Secrets and variables** → **Actions**:

| Secret | Value |
|---|---|
| `AWS_ACCOUNT_ID` | `529646246979` |
| `AWS_REGION` | `ap-southeast-2` |

### 6. Cấu hình OIDC (một lần per AWS account)

```bash
# Tạo OIDC provider nếu chưa có
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1

# Verify IAM role do Terraform tạo
aws iam get-role --role-name awstodo-dev-github-actions-role
```

---

## Deploy

Sau khi hoàn thành 6 bước trên, chỉ cần:

```bash
git add .
git commit -m "feat: initial deploy"
git push origin main
```

Pipeline tự chạy, không cần thao tác thêm gì trên VM.

Theo dõi tại: GitHub → **Actions** tab.

---

## Vận hành thường ngày

### Xem logs

```bash
# Từ master VM
kubectl logs -n todoapp deployment/backend  --tail=100 -f
kubectl logs -n todoapp deployment/frontend --tail=100 -f

# Hoặc qua Grafana/Loki
# URL: http://192.168.241.12:30000  (admin / admin123)
```

### Rollback thủ công

```bash
kubectl rollout undo deployment/backend  -n todoapp
kubectl rollout undo deployment/frontend -n todoapp
```

### Scale pods

```bash
kubectl scale deployment backend  --replicas=3 -n todoapp
kubectl scale deployment frontend --replicas=3 -n todoapp
```

### Refresh ECR token thủ công (nếu ImagePullBackOff)

ECR token hết hạn sau 12h. Pipeline tự refresh khi deploy. Nếu cần refresh thủ công:

```bash
# Từ Windows host (Git Bash)
./k8s/scripts/ecr-secret.sh ap-southeast-2 529646246979 192.168.241.10 ~/.ssh/k8s_master
```

### Init DB lại (nếu reset RDS)

```bash
# Từ Windows host
cd ansible
ansible-playbook -i inventories/dev playbooks/db.yml --tags init
```

### Cập nhật secret (nếu credentials thay đổi)

```bash
# Từ master VM — apply lại secret mới
kubectl apply -f /home/ubuntu/k8s/todoapp/secret.yaml
# Restart pods để pick up secret mới
kubectl rollout restart deployment/backend  -n todoapp
kubectl rollout restart deployment/frontend -n todoapp
```

---

## Troubleshooting

| Triệu chứng | Kiểm tra |
|---|---|
| `ImagePullBackOff` | ECR token hết hạn → chạy `ecr-secret.sh` |
| Pods `Pending` | nodeSelector sai hostname → `kubectl get nodes` |
| `CrashLoopBackOff` | `kubectl logs -n todoapp deployment/backend` |
| Health check fail | `kubectl get events -n todoapp --sort-by='.lastTimestamp'` |
| Ansible SSH fail | `ssh -i ~/.ssh/k8s_master -v ubuntu@192.168.241.10` |
| ingress 404 | `kubectl describe ingress todoapp-ingress -n todoapp` |
