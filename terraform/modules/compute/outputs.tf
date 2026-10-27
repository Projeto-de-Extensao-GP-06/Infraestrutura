# ──────────────────────────────────────────────────────────────────────────────
# modules/compute/outputs.tf
# ──────────────────────────────────────────────────────────────────────────────

output "instances" {
  description = "Mapa completo de todas as instâncias EC2 gerenciadas pelo for_each"
  value       = aws_instance.instances
}

output "app_a_id" {
  description = "ID da instancia ec2-app-a"
  value       = aws_instance.instances["app_a"].id
}

output "app_a_public_ip" {
  description = "IP publico da instancia ec2-app-a"
  value       = aws_instance.instances["app_a"].public_ip
}

output "app_a_private_ip" {
  description = "IP privado da instancia ec2-app-a"
  value       = aws_instance.instances["app_a"].private_ip
}

output "app_b_id" {
  description = "ID da instancia ec2-app-b"
  value       = aws_instance.instances["app_b"].id
}

output "app_b_public_ip" {
  description = "IP publico da instancia ec2-app-b"
  value       = aws_instance.instances["app_b"].public_ip
}

output "app_b_private_ip" {
  description = "IP privado da instancia ec2-app-b"
  value       = aws_instance.instances["app_b"].private_ip
}

output "backend_a_id" {
  description = "ID da instancia ec2-backend-a"
  value       = aws_instance.instances["backend_a"].id
}

output "backend_a_private_ip" {
  description = "IP privado da instancia ec2-backend-a"
  value       = aws_instance.instances["backend_a"].private_ip
}

output "backend_b_id" {
  description = "ID da instancia ec2-backend-b"
  value       = aws_instance.instances["backend_b"].id
}

output "backend_b_private_ip" {
  description = "IP privado da instancia ec2-backend-b"
  value       = aws_instance.instances["backend_b"].private_ip
}

output "db_id" {
  description = "ID da instancia ec2-db"
  value       = aws_instance.instances["db"].id
}

output "db_private_ip" {
  description = "IP privado da instancia ec2-db"
  value       = aws_instance.instances["db"].private_ip
}

# ── Outputs da Instancia de Observabilidade ──────────────────────────────────
output "observability_instance_id" {
  description = "ID da instancia ec2-observability (ou string vazia se desabilitada)"
  value       = try(aws_instance.observability[0].id, "")
}

output "observability_public_ip" {
  description = "IP publico da instancia ec2-observability (ou string vazia se desabilitada)"
  value       = try(aws_instance.observability[0].public_ip, "")
}

output "observability_private_ip" {
  description = "IP privado da instancia ec2-observability (ou string vazia se desabilitada)"
  value       = try(aws_instance.observability[0].private_ip, "")
}

# ── Outputs do Application Load Balancer ─────────────────────────────────────
output "alb_dns_name" {
  description = "DNS publico do Application Load Balancer"
  value       = aws_lb.app.dns_name
}

output "alb_arn" {
  description = "ARN do Application Load Balancer"
  value       = aws_lb.app.arn
}

output "alb_arn_suffix" {
  description = "ARN suffix do Application Load Balancer (utilizado para CloudWatch Metrics)"
  value       = aws_lb.app.arn_suffix
}

output "target_group_arn" {
  description = "ARN do Target Group HTTP :80"
  value       = aws_lb_target_group.app.arn
}

output "target_group_arn_suffix" {
  description = "ARN suffix do Target Group HTTP :80 (utilizado para CloudWatch Metrics)"
  value       = aws_lb_target_group.app.arn_suffix
}
