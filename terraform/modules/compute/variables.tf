# ──────────────────────────────────────────────────────────────────────────────
# modules/compute/variables.tf
# ──────────────────────────────────────────────────────────────────────────────

variable "key_name" {
  description = "Nome do Key Pair SSH na AWS para acesso às instâncias"
  type        = string
}

variable "ami_id" {
  description = "AMI ID a utilizar nas instâncias EC2 (deve bater com a AMI que está no state)"
  type        = string
}

variable "instance_type" {
  description = "Tipo das instâncias EC2 principais (app, backend, db)"
  type        = string
  default     = "t3.small"
}

variable "user_data_path" {
  description = "Caminho absoluto do script user_data a ser injetado nas instâncias. Deixe vazio para omitir."
  type        = string
  default     = ""
}

variable "instances_config" {
  description = "Mapa de configuracao para as instancias de aplicacao, backend e banco"
  type = map(object({
    subnet_id                   = string
    vpc_security_group_ids      = list(string)
    instance_type               = optional(string, null)
    iam_instance_profile        = optional(string, null)
    associate_public_ip_address = optional(bool, false)
    tags                        = map(string)
  }))
}

# ── Configuracao da Instancia de Observabilidade (Opcional) ───────────────────
variable "enable_observability" {
  description = "Se true, provisiona a instancia dedicada de observabilidade"
  type        = bool
  default     = false
}

variable "observability_config" {
  description = "Configuracoes para a instancia de observabilidade"
  type = object({
    subnet_id              = string
    vpc_security_group_ids = list(string)
    iam_instance_profile   = string
    tags                   = map(string)
  })
  default = null
}

# ── Configuracao do Application Load Balancer ────────────────────────────────
variable "alb_security_group_id" {
  description = "Security Group ID para o Application Load Balancer"
  type        = string
}

variable "alb_subnet_ids" {
  description = "Lista de IDs de subnets publicas para o ALB (minimo 2 em AZs distintas)"
  type        = list(string)
}

variable "vpc_id" {
  description = "ID da VPC para associacao ao Target Group"
  type        = string
}

variable "target_instances" {
  description = "Lista de chaves do map instances_config que devem ser registradas no Target Group do ALB (ex: ['app_a', 'app_b'])"
  type        = list(string)
  default     = ["app_a", "app_b"]
}
