# ──────────────────────────────────────────────────────────────────────────────
# Orquestração Automática do Ansible pelo Terraform (Modelo GitOps / Pezão)
# ──────────────────────────────────────────────────────────────────────────────

# ── 1. Geração Dinâmica do Inventário do Ansible ──────────────────────────────
resource "local_file" "ansible_inventory" {
  filename        = "${path.module}/../ansible/inventories/production.ini"
  file_permission = "0644"

  content = templatefile("${path.module}/templates/production.ini.tftpl", {
    app_a_public_ip         = aws_instance.app_a.public_ip
    app_b_public_ip         = aws_instance.app_b.public_ip
    backend_a_private_ip    = aws_instance.backend_a.private_ip
    backend_b_private_ip    = aws_instance.backend_b.private_ip
    db_private_ip           = aws_instance.db.private_ip
    enable_observability    = var.enable_observability
    observability_public_ip = var.enable_observability ? aws_instance.observability[0].public_ip : ""
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
    db_host              = aws_instance.db.private_ip
    mysql_database       = var.rds_db_name
    mysql_user           = var.rds_username
    mysql_password       = var.rds_password
    backend_a_ip         = aws_instance.backend_a.private_ip
    backend_b_ip         = aws_instance.backend_b.private_ip
    ecr_frontend_url     = aws_ecr_repository.frontend.repository_url
    ecr_backend_url      = aws_ecr_repository.backend.repository_url
    enable_observability = var.enable_observability
    observability_ip     = var.enable_observability ? aws_instance.observability[0].private_ip : ""
    swarm_manager_ip     = aws_instance.app_a.private_ip
  })
}

# ── 3. Disparo Automático do Ansible Playbook após a Infraestrutura estar Pronta
resource "null_resource" "run_ansible" {
  count = var.auto_run_ansible ? 1 : 0

  depends_on = [
    aws_instance.app_a,
    aws_instance.app_b,
    aws_instance.backend_a,
    aws_instance.backend_b,
    aws_instance.db,
    aws_instance.observability,
    aws_ecr_repository.frontend,
    aws_ecr_repository.backend,
    local_file.ansible_inventory,
    local_file.ansible_vars
  ]

  provisioner "local-exec" {
    working_dir = "${path.module}/../ansible"
    command     = "wsl -e bash -c \"./run_ansible.sh\""
  }
}
