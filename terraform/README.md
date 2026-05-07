# TodosK8S – Terraform Infrastructure

Highly available web application infrastructure on AWS, managed with Terraform.

## Architecture Overview

```
Internet
   │
   ▼
[WAF] ──── [ALB] (public subnets, AZ1 + AZ2)
              │
    ┌─────────┴──────────┐
    ▼                    ▼
[Web 1]             [Web 2]        ← private app subnets
(AZ1)               (AZ2)
    │                    │
    └──────┬─────────────┘
           │
    ┌──────┴──────┐
    ▼             ▼
[Redis]         [RDS]              ← private subnets
(AZ1)           (AZ1 / GP3)

[Bastion] ← public subnet AZ1, SSH from trusted IP only
[NAT GW]  ← public subnet AZ1, outbound for private subnets
[S3]      ← avatars/ + deploy/ folders
```

## Module Structure

```
terraform/
├── main.tf                  # Root – wires all modules together
├── variables.tf             # Root variables
├── outputs.tf               # Root outputs
├── terraform.tfvars.example # Copy → terraform.tfvars and fill in
├── .gitignore
└── modules/
    ├── vpc/                 # VPC (10.0.0.0/16)
    ├── subnets/             # Public, private-app, private-db subnets
    ├── igw/                 # Internet Gateway + public route table
    ├── nat/                 # NAT Gateway + private route tables
    ├── security-groups/     # ALB, Web, Bastion, Redis, RDS SGs
    ├── waf/                 # WAFv2 ACL (rate limit, SQLi, common rules)
    ├── alb/                 # ALB, target group, HTTP listener
    ├── ec2/                 # Bastion + 2 web servers
    ├── redis/               # ElastiCache Redis (single node)
    ├── rds/                 # RDS PostgreSQL 177
    ├── s3/                  # Avatar/deploy bucket
    └── iam/                 # EC2 role, GitHub OIDC role
```

## Prerequisites

- Terraform >= 1.5.0
- AWS CLI configured with admin credentials (for first-time setup)
- An existing EC2 key pair in the target region
- Your public IP address (for Bastion SSH access)

## Quick Start

### 1. Clone and configure variables

```bash
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

**Required values to fill in:**

| Variable | Description |
|---|---|
| `trusted_ip` | Your public IP in CIDR format, e.g. `1.2.3.4/32` |
| `key_name` | Name of your EC2 key pair |
| `ami_id` | Amazon Linux 2023 AMI for `ap-southeast-2` |
| `db_password` | RDS master password (use Secrets Manager in prod) |

### 2. Find the latest Amazon Linux 2023 AMI

```bash
aws ec2 describe-images \
  --owners amazon \
  --filters "Name=name,Values=al2023-ami-*-x86_64" \
  --query "sort_by(Images,&CreationDate)[-1].ImageId" \
  --region ap-southeast-2
```

### 3. Initialise and apply

```bash
terraform init
terraform plan
terraform apply
```

### 4. Configure GitHub Actions secret

After `apply`, note the `github_actions_role_arn` output and add it to your GitHub repository secrets as `AWS_ROLE_ARN`.

```bash
terraform output github_actions_role_arn
```

## Security Notes

- EC2 instances have **no public IPs** — SSH only via Bastion or SSM Session Manager
- ALB → EC2 traffic is restricted by **Security Group rules** (not 0.0.0.0/0)
- IMDSv2 is enforced on all EC2 instances
- S3 bucket has public access **fully blocked**
- RDS and ElastiCache are in **private subnets only**
- GitHub OIDC is scoped to `main` branch of `PhongHai191/TodosK8S` only
- WAF protects ALB with rate limiting, SQLi, and common rule sets

## Useful Commands

```bash
# SSH to a web server via Bastion
ssh -J ec2-user@<bastion-ip> ec2-user@<web-private-ip>

# SSM Session Manager (no SSH key needed)
aws ssm start-session --target <instance-id>

# Destroy all resources
terraform destroy
```

## Cost Estimate (ap-southeast-2, rough monthly)

| Resource | ~Cost/month |
|---|---|
| NAT Gateway | ~$35 |
| ALB | ~$20 |
| 2x t3.small EC2 | ~$30 |
| t3.micro Bastion | ~$8 |
| t3.micro RDS | ~$15 |
| t3.micro ElastiCache | ~$13 |
| S3 + WAF | ~$10 |
| **Total** | **~$130** |

> Costs vary with traffic. NAT Gateway data transfer is the most variable cost.
