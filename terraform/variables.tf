variable "region" {
  description = "Região AWS"
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR da VPC"
  default     = "10.0.0.0/20"
}

# ── Subnets Públicas (App) ──────────────────────────────────────────────────
variable "public_subnet_a_cidr" {
  description = "Subnet pública AZ-a"
  default     = "10.0.1.0/24"
}

variable "public_subnet_b_cidr" {
  description = "Subnet pública AZ-b"
  default     = "10.0.2.0/24"
}

variable "public_subnet_obs_cidr" {
  description = "Subnet pública para EC2 de observabilidade (AZ-c)"
  default     = "10.0.7.0/24"
}

# ── Subnets Privadas (Backend) ──────────────────────────────────────────────
variable "private_backend_a_cidr" {
  description = "Subnet privada backend AZ-a"
  default     = "10.0.3.0/24"
}

variable "private_backend_b_cidr" {
  description = "Subnet privada backend AZ-b"
  default     = "10.0.4.0/24"
}

# ── Subnets Privadas (Banco de Dados) ──────────────────────────────────────
variable "private_db_a_cidr" {
  description = "Subnet privada banco de dados AZ-a"
  default     = "10.0.5.0/24"
}

variable "private_db_b_cidr" {
  description = "Subnet privada banco de dados AZ-b (reservada, não usada atualmente)"
  default     = "10.0.6.0/24"
}

# ── EC2 ────────────────────────────────────────────────────────────────────
variable "ami_id" {
  description = "AMI das instâncias (Ubuntu 20.04)"
  default     = "ami-0ec10929233384c7f"
}

variable "instance_type" {
  description = "Tipo das instâncias"
  default     = "t3.small"
}

variable "observability_allowed_cidr" {
  description = "CIDR autorizado para acessar Prometheus (9090) e Grafana (3001), ex: 203.0.113.10/32"
  type        = string
  default     = null
  nullable    = true
}

variable "enable_observability_iam" {
  description = "Cria IAM role/policy/profile para observabilidade nas EC2 (requer permissao iam:CreateRole)"
  type        = bool
  default     = false
}

variable "observability_existing_instance_profile_name" {
  description = "Nome de um Instance Profile IAM ja existente para anexar nas EC2 app (opcional)"
  type        = string
  default     = null
}

variable "force_observability_aws_integrations" {
  description = "Forca CloudWatch Exporter mesmo sem IAM criado pelo Terraform"
  type        = bool
  default     = true
}

variable "enable_observability" {
  description = "Define se a infraestrutura de observabilidade (EC2 Grafana/Prometheus/Loki) deve ser provisionada"
  type        = bool
  default     = false
}

variable "auto_run_ansible" {
  description = "Dispara a execucao do Ansible Playbook automaticamente apos provisionar o Terraform"
  type        = bool
  default     = true
}

variable "auto_sync_ecr" {
  description = "Sincroniza automaticamente as imagens do Docker Hub para o Amazon ECR durante o terraform apply"
  type        = bool
  default     = true
}

variable "docker_frontend_hub_image" {
  description = "Imagem do Frontend no Docker Hub para sincronizacao no ECR"
  type        = string
  default     = "lpamorim/sgpj-frontend:latest"
}

variable "docker_backend_hub_image" {
  description = "Imagem do Backend no Docker Hub para sincronizacao no ECR"
  type        = string
  default     = "lpamorim/sgpj-backend:latest"
}

variable "enable_data_lake_iam" {
  description = "Cria IAM roles para Glue Crawlers e Jobs (bloqueado no AWS Academy - requer permissao iam:CreateRole)"
  type        = bool
  default     = false
}

variable "Key-All" {
  description = "Nome do Key Pair para acesso SSH"
  type        = string
}

# ── Banco de Dados MySQL (Container Docker na EC2 db) ─────────────────────────
variable "rds_db_name" {
  description = "Nome do banco de dados inicial"
  default     = "sgpj"
}

variable "rds_username" {
  description = "Usuario administrador do MySQL"
  default     = "admin"
}

variable "rds_password" {
  description = "Senha do administrador do MySQL"
  type        = string
  sensitive   = true
}
