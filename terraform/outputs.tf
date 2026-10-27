# ── Instâncias Públicas (App) ───────────────────────────────────────────────
output "app_a_public_ip" {
  description = "IP público da instância app-a"
  value       = module.compute.app_a_public_ip
}

output "app_b_public_ip" {
  description = "IP público da instância app-b"
  value       = module.compute.app_b_public_ip
}

output "observability_public_ip" {
  description = "IP publico da instancia de observabilidade (se habilitada)"
  value       = var.enable_observability ? module.compute.observability_public_ip : null
}

# ── Instâncias Privadas (Backend) ───────────────────────────────────────────
output "backend_a_private_ip" {
  description = "IP privado do backend-a"
  value       = module.compute.backend_a_private_ip
}

output "backend_b_private_ip" {
  description = "IP privado do backend-b"
  value       = module.compute.backend_b_private_ip
}

# ── Banco de Dados (MySQL em Container na EC2 db) ───────────────────────────
output "db_private_ip" {
  description = "IP privado do banco de dados MySQL"
  value       = module.compute.db_private_ip
}

output "db_port" {
  description = "Porta do banco de dados MySQL"
  value       = 3306
}

# ── Load Balancer ───────────────────────────────────────────────────────────
output "alb_dns" {
  description = "DNS do Load Balancer"
  value       = module.compute.alb_dns_name
}

# ── EFS ─────────────────────────────────────────────────────────────────────
output "efs_id" {
  description = "ID do EFS"
  value       = aws_efs_file_system.app_efs.id
}

output "efs_dns_name" {
  description = "DNS name do EFS"
  value       = aws_efs_file_system.app_efs.dns_name
}

# ── Repositórios ECR ────────────────────────────────────────────────────────
output "ecr_frontend_url" {
  description = "URL do repositório ECR do frontend"
  value       = aws_ecr_repository.frontend.repository_url
}

output "ecr_backend_url" {
  description = "URL do repositório ECR do backend"
  value       = aws_ecr_repository.backend.repository_url
}

# ── Data Lake Ingestion (Lambda + S3 External) ──────────────────────────────
output "s3_external_bucket" {
  description = "Nome do bucket S3 de dados externos"
  value       = local.external_bucket
}

output "lambda_ingestion_arn" {
  description = "ARN da função Lambda de ingestão"
  value       = var.enable_lambda_ingestion ? aws_lambda_function.data_ingestion[0].arn : ""
}
