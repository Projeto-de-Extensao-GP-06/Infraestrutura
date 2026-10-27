# ──────────────────────────────────────────────────────────────────────────────
# modules/compute/main.tf
# ──────────────────────────────────────────────────────────────────────────────

# ── Instâncias Padronizadas (app_a, app_b, backend_a, backend_b, db) ──────────
resource "aws_instance" "instances" {
  for_each = var.instances_config

  ami                         = var.ami_id
  instance_type               = coalesce(each.value.instance_type, var.instance_type)
  key_name                    = var.key_name
  subnet_id                   = each.value.subnet_id
  vpc_security_group_ids      = each.value.vpc_security_group_ids
  iam_instance_profile        = each.value.iam_instance_profile
  associate_public_ip_address = each.value.associate_public_ip_address
  user_data                   = var.user_data_path != "" ? file(var.user_data_path) : null

  tags = each.value.tags
}

# ── Instância de Observabilidade (Opcional - Condicional) ─────────────────────
resource "aws_instance" "observability" {
  count = var.enable_observability && var.observability_config != null ? 1 : 0

  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = var.key_name
  subnet_id                   = var.observability_config.subnet_id
  vpc_security_group_ids      = var.observability_config.vpc_security_group_ids
  associate_public_ip_address = true
  iam_instance_profile        = var.observability_config.iam_instance_profile
  user_data                   = var.user_data_path != "" ? file(var.user_data_path) : null

  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
    tags                  = { Name = "ebs-observability-sgpj" }
  }

  tags = var.observability_config.tags
}

# ── Application Load Balancer (ALB) ──────────────────────────────────────────
resource "aws_lb" "app" {
  name               = "alb-app"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.alb_subnet_ids

  tags = { Name = "alb-app" }
}

# ── Target Group HTTP :80 ────────────────────────────────────────────────────
resource "aws_lb_target_group" "app" {
  name     = "tg-app"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

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

# ── Listener HTTP :80 ────────────────────────────────────────────────────────
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ── Target Group Attachment (Apenas nós de Frontend App) ─────────────────────
resource "aws_lb_target_group_attachment" "app" {
  for_each = toset(var.target_instances)

  target_group_arn = aws_lb_target_group.app.arn
  target_id        = aws_instance.instances[each.value].id
  port             = 80
}
