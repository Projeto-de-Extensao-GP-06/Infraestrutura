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
  description = "IP publico da instancia de observabilidade (se habilitada)"
  value       = try(aws_instance.observability[0].public_ip, null)
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

# ── Banco de Dados (MySQL em Container na EC2 db) ───────────────────────────
output "db_private_ip" {
  description = "IP privado do banco de dados MySQL"
  value       = aws_instance.db.private_ip
}

output "db_port" {
  description = "Porta do banco de dados MySQL"
  value       = 3306
}

# ── Load Balancer ───────────────────────────────────────────────────────────
output "alb_dns" {
  description = "DNS do Load Balancer"
  value       = aws_lb.app.dns_name
}

# ── EFS ─────────────────────────────────────────────────────────────────────
output "efs_id" {
  description = "ID do EFS"
  value       = aws_efs_file_system.app_efs.id
}

output "efs_dns_name" {
  description = "DNS do EFS para montagem nas instancias"
  value       = aws_efs_file_system.app_efs.dns_name
}

output "observability_aws_auth_enabled" {
  description = "Indica se as EC2 app possuem autenticacao AWS para exporters/Alertmanager"
  value       = var.force_observability_aws_integrations || var.enable_observability_iam || (var.observability_existing_instance_profile_name != null && var.observability_existing_instance_profile_name != "")
}
