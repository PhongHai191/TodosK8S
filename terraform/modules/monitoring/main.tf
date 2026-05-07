terraform {
  required_providers {
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }
}

resource "tls_private_key" "monitoring" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "monitoring" {
  key_name   = "${var.project_name}-${var.environment}-monitoring-key"
  public_key = tls_private_key.monitoring.public_key_openssh
  tags       = { Name = "${var.project_name}-${var.environment}-monitoring-key" }
}

resource "aws_secretsmanager_secret" "monitoring_key" {
  name                    = "${var.project_name}/${var.environment}/keypair/monitoring"
  description             = "Private SSH key for monitoring host"
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = 0
  tags                    = { Name = "${var.project_name}-${var.environment}-monitoring-key" }
}

resource "aws_secretsmanager_secret_version" "monitoring_key" {
  secret_id     = aws_secretsmanager_secret.monitoring_key.id
  secret_string = tls_private_key.monitoring.private_key_pem
}

resource "aws_instance" "monitoring" {
  ami                         = var.ami_id
  instance_type               = "t3.small"
  subnet_id                   = var.public_subnet_id
  vpc_security_group_ids      = [var.monitoring_sg_id]
  key_name                    = aws_key_pair.monitoring.key_name
  iam_instance_profile        = var.ec2_instance_profile
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

  user_data = base64encode(<<-EOF
    #!/bin/bash
    yum update -y
    yum install -y amazon-ssm-agent
    systemctl enable amazon-ssm-agent
    systemctl start amazon-ssm-agent
  EOF
  )

  tags = {
    Name        = "${var.project_name}-${var.environment}-monitoring"
    Role        = "monitoring"
    Project     = var.project_name
    Environment = var.environment
  }

  depends_on = [aws_key_pair.monitoring]
}
