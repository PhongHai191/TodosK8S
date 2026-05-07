terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "awstodo-terraform-state-529646246979"
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
  private_app_cidrs    = var.private_app_cidrs
  private_db_cidrs     = var.private_db_cidrs
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
  source        = "../../modules/iam"
  project_name  = var.project_name
  environment   = var.environment
  s3_bucket_arn = module.s3.bucket_arn
  github_repo   = var.github_repo
}

# ── Redis ──────────────────────────────────────────────────────────────────────
module "redis" {
  source                 = "../../modules/redis"
  project_name           = var.project_name
  environment            = var.environment
  private_app_subnet_ids = module.network.private_app_subnet_ids
  redis_sg_id            = module.security_groups.redis_sg_id
}

# ── RDS ────────────────────────────────────────────────────────────────────────
module "rds" {
  source                = "../../modules/rds"
  project_name          = var.project_name
  environment           = var.environment
  private_db_subnet_ids = module.network.private_db_subnet_ids
  rds_sg_id             = module.security_groups.rds_sg_id
  kms_key_arn           = module.kms.rds_kms_key_arn
  db_username           = var.db_username
  db_password           = var.db_password
  db_name               = var.db_name
  db_instance_class     = var.db_instance_class
}

# ── S3 ─────────────────────────────────────────────────────────────────────────
module "s3" {
  source       = "../../modules/s3"
  project_name = var.project_name
  environment  = var.environment
  bucket_name  = var.s3_bucket_name
}
