# ── DB Subnet Group ───────────────────────────────────────────────────────────
resource "aws_db_subnet_group" "main" {
  name       = "${var.project_name}-${var.environment}-db-subnet-group"
  subnet_ids = var.private_db_subnet_ids

  tags = { Name = "${var.project_name}-${var.environment}-db-subnet-group" }
}

# ── RDS Parameter Group ───────────────────────────────────────────────────────
resource "aws_db_parameter_group" "postgres" {
  name   = "${var.project_name}-${var.environment}-pg17"
  family = "postgres17"

  parameter {
    name  = "log_connections"
    value = "1"
  }

  parameter {
    name  = "log_disconnections"
    value = "1"
  }

  tags = { Name = "${var.project_name}-${var.environment}-pg17" }
}

# ── RDS Instance ──────────────────────────────────────────────────────────────
resource "aws_db_instance" "main" {
  identifier = "${var.project_name}-${var.environment}-db"

  engine                = "postgres"
  engine_version        = "17"
  instance_class        = var.db_instance_class
  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true
  kms_key_id            = var.kms_key_arn

  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [var.rds_sg_id]
  parameter_group_name   = aws_db_parameter_group.postgres.name

  multi_az                = false
  backup_retention_period = 1
  backup_window           = "03:00-04:00"
  maintenance_window      = "sun:04:00-sun:05:00"

  publicly_accessible       = true
  port                      = 5432
  deletion_protection       = false
  skip_final_snapshot       = true

  tags = { Name = "${var.project_name}-${var.environment}-db" }
}

# ── DB Connection Secret (Secrets Manager) ────────────────────────────────────
resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${var.project_name}/${var.environment}/db/credentials"
  description             = "Database connection info for ${var.project_name} ${var.environment}"
  recovery_window_in_days = 0

  tags = { Name = "${var.project_name}-${var.environment}-db-credentials" }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id

  secret_string = jsonencode({
    host     = aws_db_instance.main.address
    port     = aws_db_instance.main.port
    dbname   = aws_db_instance.main.db_name
    username = aws_db_instance.main.username
    password = var.db_password
  })
}
