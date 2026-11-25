# --- DB Subnet Group ---
resource "aws_db_subnet_group" "aurora" {
  name        = "${var.project_name}-${var.environment}-aurora-subnets"
  description = "Subnet group for Aurora PostgreSQL in isolated database subnets"
  subnet_ids  = var.database_subnet_ids

  tags = {
    Name = "${var.project_name}-${var.environment}-aurora-subnets"
  }
}

# --- DB Cluster Parameter Group (enabling pgvector) ---
resource "aws_rds_cluster_parameter_group" "aurora" {
  name        = "${var.project_name}-${var.environment}-aurora-pg16"
  family      = "aurora-postgresql16"
  description = "Cluster parameter group for Aurora PostgreSQL 16 with pgvector extension enabled"

  parameter {
    name         = "shared_preload_libraries"
    value        = "vector"
    apply_method = "pending-reboot"
  }

  parameter {
    name  = "rds.force_ssl"
    value = "1"
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-aurora-pg16"
  }
}

# --- Database Credentials in Secrets Manager ---
resource "random_password" "db_master_password" {
  length           = 32
  special          = true
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "aws_secretsmanager_secret" "db_credentials" {
  name                    = "${var.project_name}/${var.environment}/aurora/master-credentials"
  description             = "Master credentials for Aurora PostgreSQL pgvector instance"
  kms_key_id              = var.kms_key_arn
  recovery_window_in_days = 0

  tags = {
    Name = "${var.project_name}-${var.environment}-db-secret"
  }
}

resource "aws_secretsmanager_secret_version" "db_credentials" {
  secret_id = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    engine   = "postgres"
    host     = aws_rds_cluster.postgresql.endpoint
    port     = 5432
    username = "postgres"
    password = random_password.db_master_password.result
    database = var.database_name
  })
}

# --- Aurora Serverless v2 PostgreSQL Cluster ---
resource "aws_rds_cluster" "postgresql" {
  cluster_identifier              = "${var.project_name}-${var.environment}-aurora"
  engine                          = "aurora-postgresql"
  engine_mode                     = "provisioned"
  engine_version                  = "16.1"
  database_name                   = var.database_name
  master_username                 = "postgres"
  master_password                 = random_password.db_master_password.result
  db_subnet_group_name            = aws_db_subnet_group.aurora.name
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.aurora.name
  vpc_security_group_ids          = [var.aurora_security_group_id]
  storage_encrypted               = true
  kms_key_id                      = var.kms_key_arn
  skip_final_snapshot             = true
  deletion_protection             = false
  copy_tags_to_snapshot           = true

  serverlessv2_scaling_configuration {
    min_capacity = var.min_capacity
    max_capacity = var.max_capacity
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-aurora-pgvector"
  }
}

# Primary DB Instance (Serverless v2)
resource "aws_rds_cluster_instance" "writer" {
  identifier           = "${var.project_name}-${var.environment}-aurora-writer"
  cluster_identifier   = aws_rds_cluster.postgresql.id
  instance_class       = "db.serverless"
  engine               = aws_rds_cluster.postgresql.engine
  engine_version       = aws_rds_cluster.postgresql.engine_version
  db_subnet_group_name = aws_db_subnet_group.aurora.name
  publicly_accessible  = false

  tags = {
    Name = "${var.project_name}-${var.environment}-aurora-instance-writer"
  }
}
