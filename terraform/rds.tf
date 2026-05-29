# RDS MySQL — acessível pela ec2-db e pelas instâncias de backend

# ── DB Subnet Group (exige pelo menos 2 AZs) ──────────────────────────────
resource "aws_db_subnet_group" "mysql" {
  name        = "sgpj-rds-subnet-group"
  description = "Subnet group do RDS MySQL (AZ-a e AZ-b)"
  subnet_ids  = [
    aws_subnet.private_db_a.id,
    aws_subnet.private_db_b.id,
  ]

  tags = { Name = "sgpj-rds-subnet-group" }
}

# ── RDS MySQL ──────────────────────────────────────────────────────────────
resource "aws_db_instance" "mysql" {
  identifier             = "sgpj-mysql"
  engine                 = "mysql"
  engine_version         = "8.0"
  instance_class         = var.rds_instance_class
  allocated_storage      = var.rds_allocated_storage
  max_allocated_storage  = var.rds_max_allocated_storage
  storage_type           = "gp3"
  storage_encrypted      = true

  db_name  = var.rds_db_name
  username = var.rds_username
  password = var.rds_password

  db_subnet_group_name   = aws_db_subnet_group.mysql.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  multi_az               = false   # mude para true em produção
  publicly_accessible    = false
  deletion_protection    = false   # mude para true em produção
  skip_final_snapshot    = true    # mude para false em produção

  backup_retention_period = 7
  backup_window           = "03:00-04:00"
  maintenance_window      = "Mon:04:00-Mon:05:00"

  tags = { Name = "sgpj-rds-mysql" }
}
