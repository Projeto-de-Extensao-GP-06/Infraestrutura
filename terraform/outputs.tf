# ── Instâncias Públicas (App) ───────────────────────────────────────────────
output "app_a_public_ip" {
  description = "IP público da instância app-a"
  value       = aws_instance.app_a.public_ip
}

output "app_b_public_ip" {
  description = "IP público da instância app-b"
  value       = aws_instance.app_b.public_ip
}

output "observability_public_ip" {
  description = "IP público da instância de observabilidade"
  value       = aws_instance.observability.public_ip
}

# ── Instâncias Privadas (Backend) ───────────────────────────────────────────
output "backend_a_private_ip" {
  description = "IP privado do backend-a"
  value       = aws_instance.backend_a.private_ip
}

output "backend_b_private_ip" {
  description = "IP privado do backend-b"
  value       = aws_instance.backend_b.private_ip
}

# ── Banco de Dados ──────────────────────────────────────────────────────────
output "db_private_ip" {
  description = "IP privado do banco de dados"
  value       = aws_instance.db.private_ip
}

# ── Load Balancer ───────────────────────────────────────────────────────────
output "alb_dns" {
  description = "DNS do Load Balancer"
  value       = aws_lb.app.dns_name
}

# ── EFS ─────────────────────────────────────────────────────────────────────
output "efs_id" {
  description = "ID do EFS"
  value       = data.aws_efs_file_system.app_efs.id
}

output "efs_dns_name" {
  description = "DNS do EFS para montagem nas instâncias"
  value       = data.aws_efs_file_system.app_efs.dns_name
}

# ── RDS MySQL ────────────────────────────────────────────────────────────────
output "rds_endpoint" {
  description = "Endpoint de conexão do RDS MySQL"
  value       = aws_db_instance.mysql.endpoint
}

output "rds_port" {
  description = "Porta do RDS MySQL"
  value       = aws_db_instance.mysql.port
}

output "rds_db_name" {
  description = "Nome do banco de dados"
  value       = aws_db_instance.mysql.db_name
}

output "observability_aws_auth_enabled" {
  description = "Indica se as EC2 app possuem autenticacao AWS para exporters/Alertmanager"
  value       = var.force_observability_aws_integrations || var.enable_observability_iam || (var.observability_existing_instance_profile_name != null && var.observability_existing_instance_profile_name != "")
}
