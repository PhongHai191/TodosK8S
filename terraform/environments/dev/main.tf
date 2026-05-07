terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "todosk8s-terraform-state-529646246979"
    key            = "dev/terraform.tfstate"
    region         = "ap-southeast-2"
    use_lockfile   = true
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}

# ── KMS Keys ───────────────────────────────────────────────────────────────────
module "kms" {
  source       = "../../modules/kms"
  project_name = var.project_name
  environment  = var.environment
}

# ── Network (VPC + Subnets + IGW + NAT) ───────────────────────────────────────
module "network" {
  source               = "../../modules/network"
  project_name         = var.project_name
  environment          = var.environment
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
}

# ── Security Groups ────────────────────────────────────────────────────────────
module "security_groups" {
  source       = "../../modules/security-groups"
  project_name = var.project_name
  environment  = var.environment
  vpc_id       = module.network.vpc_id
  trusted_ip   = var.trusted_ip
}

# ── IAM ────────────────────────────────────────────────────────────────────────
module "iam" {
  source       = "../../modules/iam"
  project_name = var.project_name
  environment  = var.environment
  github_repo  = var.github_repo
}

# ── Redis ──────────────────────────────────────────────────────────────────────
module "redis" {
  source            = "../../modules/redis"
  project_name      = var.project_name
  environment       = var.environment
  public_subnet_ids = module.network.public_subnet_ids
  redis_sg_id       = module.security_groups.redis_sg_id
}

# ── RDS ────────────────────────────────────────────────────────────────────────
module "rds" {
  source            = "../../modules/rds"
  project_name      = var.project_name
  environment       = var.environment
  public_subnet_ids = module.network.public_subnet_ids
  rds_sg_id         = module.security_groups.rds_sg_id
  kms_key_arn       = module.kms.rds_kms_key_arn
  db_username       = var.db_username
  db_password       = var.db_password
  db_name           = var.db_name
  db_instance_class = var.db_instance_class
}

# ── IAM User for backend pod S3 access (K8s pods có no instance profile) ──────
resource "aws_iam_user" "backend_s3" {
  name = "${var.project_name}-${var.environment}-backend-s3"
  tags = { Name = "${var.project_name}-${var.environment}-backend-s3" }
}

resource "aws_iam_user_policy" "backend_s3" {
  name = "${var.project_name}-${var.environment}-backend-s3"
  user = aws_iam_user.backend_s3.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3ListBucket"
        Effect = "Allow"
        Action = ["s3:ListBucket"]
        Resource = [module.s3.bucket_arn]
      },
      {
        Sid    = "S3AvatarAccess"
        Effect = "Allow"
        Action = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = ["${module.s3.bucket_arn}/avatars/*"]
      }
    ]
  })
}

resource "aws_iam_access_key" "backend_s3" {
  user = aws_iam_user.backend_s3.name
}

# ── ECR Repositories ───────────────────────────────────────────────────────────
resource "aws_ecr_repository" "backend" {
  name                 = "${var.project_name}-backend"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Name = "${var.project_name}-backend" }
}

resource "aws_ecr_repository" "nginx" {
  name                 = "${var.project_name}-nginx"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = { Name = "${var.project_name}-nginx" }
}

resource "aws_ecr_lifecycle_policy" "backend" {
  repository = aws_ecr_repository.backend.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

resource "aws_ecr_lifecycle_policy" "nginx" {
  repository = aws_ecr_repository.nginx.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = { type = "expire" }
    }]
  })
}

# ── S3 ─────────────────────────────────────────────────────────────────────────
module "s3" {
  source       = "../../modules/s3"
  project_name = var.project_name
  environment  = var.environment
  bucket_name  = var.s3_bucket_name
}
