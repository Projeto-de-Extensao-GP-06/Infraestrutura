# ──────────────────────────────────────────────────────────────────────────────
# Orquestração Automática do Ansible pelo Terraform (Modelo GitOps / Pezão)
# ──────────────────────────────────────────────────────────────────────────────

# ── 1. Geração Dinâmica do Inventário do Ansible ──────────────────────────────
resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/../ansible/inventories/production.ini"
  file_permission = "0644"

  content = templatefile("${path.module}/templates/production.ini.tftpl", {
    app_a_public_ip         = module.compute.app_a_public_ip
    app_b_public_ip         = module.compute.app_b_public_ip
    backend_a_private_ip    = module.compute.backend_a_private_ip
    backend_b_private_ip    = module.compute.backend_b_private_ip
    db_private_ip           = module.compute.db_private_ip
    enable_observability    = var.enable_observability
    observability_public_ip = var.enable_observability ? module.compute.observability_public_ip : ""
    efs_dns_name            = aws_efs_file_system.app_efs.dns_name
    key_name                = var.Key-All
  })
}

# ── 2. Geração Dinâmica das Variáveis Globais do Ansible ───────────────────────
resource "local_file" "ansible_vars" {
  filename        = "${path.module}/../ansible/inventories/group_vars/all.yml"
  file_permission = "0644"

  content = templatefile("${path.module}/templates/all.yml.tftpl", {
    aws_region           = var.region
    efs_dns              = aws_efs_file_system.app_efs.dns_name
    db_host              = module.compute.db_private_ip
    mysql_database       = var.rds_db_name
    mysql_user           = var.rds_username
    mysql_password       = var.rds_password
    backend_a_ip         = module.compute.backend_a_private_ip
    backend_b_ip         = module.compute.backend_b_private_ip
    ecr_frontend_url     = aws_ecr_repository.frontend.repository_url
    ecr_backend_url      = aws_ecr_repository.backend.repository_url
    ecr_agent_url        = aws_ecr_repository.agent.repository_url
    enable_observability = var.enable_observability
    observability_ip     = var.enable_observability ? module.compute.observability_private_ip : ""
    bronze_bucket        = local.bronze_bucket
  })
}

# ── 3. Disparo Automático do Ansible Playbook após a Infraestrutura estar Pronta
resource "null_resource" "run_ansible" {
  count = var.auto_run_ansible ? 1 : 0

  depends_on = [
    module.compute,
    aws_ecr_repository.frontend,
    aws_ecr_repository.backend,
    local_file.ansible_inventory,
    local_file.ansible_vars
  ]

  provisioner "local-exec" {
    working_dir = "${path.module}/../ansible"
    # O Terraform (local-exec) roda no PowerShell. O WSL nao herda variaveis de
    # ambiente automaticamente, entao usamos o run_ansible.sh que faz o fallback
    # via aws configure, e o ECR token agora e obtido na EC2 Manager (nao mais
    # via delegate_to: localhost) — eliminando a dependencia de credenciais no WSL.
    command = "wsl -e bash -c \"./run_ansible.sh\""
  }
}
