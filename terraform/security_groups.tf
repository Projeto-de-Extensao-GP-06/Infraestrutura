# ── ALB ────────────────────────────────────────────────────────────────────
resource "aws_security_group" "alb" {
  name        = "alb"
  description = "Security group do Load Balancer"
  vpc_id      = aws_vpc.sgpj_vpc.id

  ingress {
    description = "HTTP publico"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "alb" }
}

# ── Instâncias Públicas (App) ───────────────────────────────────────────────
resource "aws_security_group" "app" {
  name        = "app-public"
  description = "Security group das instancias de aplicacao publica"
  vpc_id      = aws_vpc.sgpj_vpc.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "RabbitMQ Management UI"
    from_port   = 15672
    to_port     = 15672
    protocol    = "tcp"
    cidr_blocks = [var.observability_allowed_cidr != null && var.observability_allowed_cidr != "" ? var.observability_allowed_cidr : "0.0.0.0/0"]
  }

  ingress {
    description = "Node Exporter (apenas da VPC)"
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "app-public" }
}

# ── Instâncias Privadas (Backend) ───────────────────────────────────────────
resource "aws_security_group" "backend" {
  name        = "backend-private"
  description = "Security group das instancias de backend privadas"
  vpc_id      = aws_vpc.sgpj_vpc.id

  ingress {
    description = "SSH (apenas da VPC)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "Spring Boot"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "RabbitMQ AMQP (apenas da VPC)"
    from_port   = 5672
    to_port     = 5672
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "RabbitMQ Management UI (apenas da VPC)"
    from_port   = 15672
    to_port     = 15672
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "Node Exporter (apenas da VPC)"
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "backend-private" }
}

# ── Instância do Banco de Dados ─────────────────────────────────────────────
resource "aws_security_group" "db" {
  name        = "db-private"
  description = "Security group da instancia de banco de dados"
  vpc_id      = aws_vpc.sgpj_vpc.id

  ingress {
    description     = "MySQL (apenas do backend)"
    from_port       = 3306
    to_port         = 3306
    protocol        = "tcp"
    security_groups = [aws_security_group.backend.id]
  }

  ingress {
    description = "SSH (apenas da VPC)"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "Node Exporter (apenas da VPC)"
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "db-private" }
}

# ── EC2 Observabilidade (Opcional) ──────────────────────────────────────────
resource "aws_security_group" "observability" {
  count       = var.enable_observability ? 1 : 0
  name        = "observability"
  description = "Security group da instancia dedicada de observabilidade"
  vpc_id      = aws_vpc.sgpj_vpc.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  dynamic "ingress" {
    for_each = var.observability_allowed_cidr != null ? [1] : []
    content {
      description = "Prometheus restrito por CIDR"
      from_port   = 9090
      to_port     = 9090
      protocol    = "tcp"
      cidr_blocks = [var.observability_allowed_cidr]
    }
  }

  dynamic "ingress" {
    for_each = var.observability_allowed_cidr != null ? [1] : []
    content {
      description = "Grafana restrito por CIDR"
      from_port   = 3001
      to_port     = 3001
      protocol    = "tcp"
      cidr_blocks = [var.observability_allowed_cidr]
    }
  }

  dynamic "ingress" {
    for_each = var.observability_allowed_cidr != null ? [1] : []
    content {
      description = "Alertmanager restrito por CIDR"
      from_port   = 9093
      to_port     = 9093
      protocol    = "tcp"
      cidr_blocks = [var.observability_allowed_cidr]
    }
  }

  ingress {
    description = "Loki ingest (agents da VPC)"
    from_port   = 3100
    to_port     = 3100
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  ingress {
    description = "Node Exporter (scrape local via VPC)"
    from_port   = 9100
    to_port     = 9100
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "observability" }
}

# ── EFS ─────────────────────────────────────────────────────────────────────
resource "aws_security_group" "efs" {
  name        = "efs"
  description = "Security group do EFS - NFS restrito a VPC"
  vpc_id      = aws_vpc.sgpj_vpc.id

  ingress {
    description = "NFS da VPC"
    from_port   = 2049
    to_port     = 2049
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "efs" }
}
