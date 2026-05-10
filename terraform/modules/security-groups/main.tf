# ── Security Group Definitions ────────────────────────────────────────────────
resource "aws_security_group" "redis" {
  name        = "${var.project_name}-${var.environment}-redis-sg"
  description = "Security group for ElastiCache Redis"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.project_name}-${var.environment}-redis-sg" }
}

resource "aws_security_group" "rds" {
  name        = "${var.project_name}-${var.environment}-rds-sg"
  description = "Security group for RDS PostgreSQL"
  vpc_id      = var.vpc_id
  tags        = { Name = "${var.project_name}-${var.environment}-rds-sg" }
}

# ── Redis Rules ───────────────────────────────────────────────────────────────
resource "aws_security_group_rule" "redis_ingress_trusted" {
  type              = "ingress"
  description       = "Redis from trusted IP (K8s local dev)"
  security_group_id = aws_security_group.redis.id
  from_port         = 6379
  to_port           = 6379
  protocol          = "tcp"
  cidr_blocks       = var.trusted_ips
}

resource "aws_security_group_rule" "redis_egress_all" {
  type              = "egress"
  description       = "Allow all outbound"
  security_group_id = aws_security_group.redis.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

# ── RDS Rules ─────────────────────────────────────────────────────────────────
resource "aws_security_group_rule" "rds_ingress_trusted" {
  type              = "ingress"
  description       = "PostgreSQL from trusted IP (K8s local dev)"
  security_group_id = aws_security_group.rds.id
  from_port         = 5432
  to_port           = 5432
  protocol          = "tcp"
  cidr_blocks       = var.trusted_ips
}

resource "aws_security_group_rule" "rds_egress_all" {
  type              = "egress"
  description       = "Allow all outbound"
  security_group_id = aws_security_group.rds.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}
