terraform {
  required_providers {
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

# ─────────────────────────────────────────────────────────────────────────────
# SSH Key Pairs
# ─────────────────────────────────────────────────────────────────────────────

# ── Bastion Key ───────────────────────────────────────────────────────────────
resource "tls_private_key" "bastion" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "bastion" {
  key_name   = "${var.project_name}-${var.environment}-bastion-key"
  public_key = tls_private_key.bastion.public_key_openssh

  tags = { Name = "${var.project_name}-${var.environment}-bastion-key" }
}

resource "aws_secretsmanager_secret" "bastion_key" {
  name                    = "${var.project_name}/${var.environment}/keypair/bastion"
  description             = "Private SSH key for bastion host"
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = 0

  tags = { Name = "${var.project_name}-${var.environment}-bastion-key" }
}

resource "aws_secretsmanager_secret_version" "bastion_key" {
  secret_id     = aws_secretsmanager_secret.bastion_key.id
  secret_string = tls_private_key.bastion.private_key_pem
}

# ── Web Server Keys ───────────────────────────────────────────────────────────
resource "tls_private_key" "web" {
  count     = 2
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "web" {
  count      = 2
  key_name   = "${var.project_name}-${var.environment}-web-${count.index + 1}-key"
  public_key = tls_private_key.web[count.index].public_key_openssh

  tags = { Name = "${var.project_name}-${var.environment}-web-${count.index + 1}-key" }
}

resource "aws_secretsmanager_secret" "web_key" {
  count                   = 2
  name                    = "${var.project_name}/${var.environment}/keypair/web-${count.index + 1}"
  description             = "Private SSH key for web server ${count.index + 1}"
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = 0

  tags = { Name = "${var.project_name}-${var.environment}-web-${count.index + 1}-key" }
}

resource "aws_secretsmanager_secret_version" "web_key" {
  count         = 2
  secret_id     = aws_secretsmanager_secret.web_key[count.index].id
  secret_string = tls_private_key.web[count.index].private_key_pem
}

# ─────────────────────────────────────────────────────────────────────────────
# EC2 Instances
# ─────────────────────────────────────────────────────────────────────────────

# ── Bastion Host ──────────────────────────────────────────────────────────────
resource "aws_instance" "bastion" {
  ami                         = var.ami_id
  instance_type               = "t3.micro"
  subnet_id                   = var.public_subnet_ids[0]
  vpc_security_group_ids      = [var.bastion_sg_id]
  key_name                    = aws_key_pair.bastion.key_name
  associate_public_ip_address = true

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    delete_on_termination = true
    encrypted             = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-bastion"
    Role = "bastion"
  }

  depends_on = [aws_key_pair.bastion]
}

# ── Web Servers ────────────────────────────────────────────────────────────────
resource "aws_instance" "web" {
  count                       = 2
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = var.private_app_subnet_ids[count.index]
  vpc_security_group_ids      = [var.web_sg_id]
  key_name                    = aws_key_pair.web[count.index].key_name
  iam_instance_profile        = var.ec2_instance_profile
  associate_public_ip_address = false

  metadata_options {
    http_tokens = "required"
  }

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 30
    delete_on_termination = true
    encrypted             = true
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y amazon-ssm-agent
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent
  EOF
  )

  tags = {
    Name = "${var.project_name}-${var.environment}-web-${count.index + 1}"
    Role = "web"
  }

  depends_on = [aws_key_pair.web]
}

# ── ALB Target Group Attachments: Frontend (port 80) ─────────────────────────
resource "aws_lb_target_group_attachment" "web_frontend" {
  count            = length(aws_instance.web)
  target_group_arn = var.frontend_target_group_arn
  target_id        = aws_instance.web[count.index].id
  port             = 80
}

# ── ALB Target Group Attachments: Backend (port 3000) ────────────────────────
resource "aws_lb_target_group_attachment" "web_backend" {
  count            = length(aws_instance.web)
  target_group_arn = var.backend_target_group_arn
  target_id        = aws_instance.web[count.index].id
  port             = 3000
}
