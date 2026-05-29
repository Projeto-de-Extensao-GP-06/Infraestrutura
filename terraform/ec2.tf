# ── Instâncias Públicas (App — React + Nginx) ───────────────────────────────
resource "aws_instance" "app_a" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public_a.id
  vpc_security_group_ids      = [aws_security_group.app.id]
  iam_instance_profile        = var.enable_observability_iam ? aws_iam_instance_profile.observability_ec2_profile[0].name : var.observability_existing_instance_profile_name
  key_name                    = var.Key-All
  associate_public_ip_address = true
  user_data                   = file("${path.module}/../scripts/util/bootstrap.sh")

  tags = { Name = "ec2-app-a" }
}

resource "aws_instance" "app_b" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public_b.id
  vpc_security_group_ids      = [aws_security_group.app.id]
  iam_instance_profile        = var.enable_observability_iam ? aws_iam_instance_profile.observability_ec2_profile[0].name : var.observability_existing_instance_profile_name
  key_name                    = var.Key-All
  associate_public_ip_address = true
  user_data                   = file("${path.module}/../scripts/util/bootstrap.sh")

  tags = { Name = "ec2-app-b" }
}

# ── Instâncias Privadas (Backend) ───────────────────────────────────────────
resource "aws_instance" "backend_a" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private_backend_a.id
  vpc_security_group_ids = [aws_security_group.backend.id]
  key_name               = var.Key-All
  # iam_instance_profile   = aws_iam_instance_profile.backend_s3.name
  user_data = file("${path.module}/../scripts/util/bootstrap.sh")

  tags = { Name = "ec2-backend-a" }
}

resource "aws_instance" "backend_b" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private_backend_b.id
  vpc_security_group_ids = [aws_security_group.backend.id]
  key_name               = var.Key-All
  # iam_instance_profile   = aws_iam_instance_profile.backend_s3.name
  user_data = file("${path.module}/../scripts/util/bootstrap.sh")

  tags = { Name = "ec2-backend-b" }
}

# ── Instância Privada (Banco de Dados) ─────────────────────────────────────
resource "aws_instance" "db" {
  ami                    = var.ami_id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.private_db_a.id
  vpc_security_group_ids = [aws_security_group.db.id]
  key_name               = var.Key-All
  user_data              = file("${path.module}/../scripts/util/bootstrap.sh")

  tags = { Name = "ec2-db" }
}

# ── Instância de Observabilidade (AZ-c — dedicada) ──────────────────────────
resource "aws_instance" "observability" {
  ami                         = var.ami_id
  instance_type               = var.instance_type
  subnet_id                   = aws_subnet.public_obs.id
  vpc_security_group_ids      = [aws_security_group.observability.id]
  iam_instance_profile        = var.enable_observability_iam ? aws_iam_instance_profile.observability_ec2_profile[0].name : var.observability_existing_instance_profile_name
  key_name                    = var.Key-All
  associate_public_ip_address = true
  user_data                   = file("${path.module}/../scripts/util/bootstrap.sh")

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
  }

  tags = { Name = "ec2-observability" }
}

# ── Application Load Balancer ───────────────────────────────────────────────
resource "aws_lb" "app" {
  name               = "alb-app"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]

  tags = { Name = "alb-app" }
}

resource "aws_lb_target_group" "app" {
  name     = "tg-app"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.sgpj_vpc.id

  health_check {
    path                = "/"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = { Name = "tg-app" }
}

resource "aws_lb_target_group_attachment" "app_a" {
  target_group_arn = aws_lb_target_group.app.arn
  target_id        = aws_instance.app_a.id
  port             = 80
}

resource "aws_lb_target_group_attachment" "app_b" {
  target_group_arn = aws_lb_target_group.app.arn
  target_id        = aws_instance.app_b.id
  port             = 80
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}
