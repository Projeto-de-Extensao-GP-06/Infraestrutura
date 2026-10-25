#!/usr/bin/env bash
set -e

# Navega para o diretorio do script (infra/ansible)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

export ANSIBLE_CONFIG=./ansible.cfg

# Propaga credenciais AWS do Windows para o WSL (o Terraform roda no PowerShell,
# mas o WSL nao herda variaveis de ambiente automaticamente).
# Se as variaveis ja estiverem definidas no WSL, os exports abaixo sao no-ops.
if [[ -z "${AWS_ACCESS_KEY_ID:-}" ]]; then
  # Tenta ler do aws configure (perfil default) como fallback
  export AWS_ACCESS_KEY_ID=$(aws configure get aws_access_key_id 2>/dev/null || true)
  export AWS_SECRET_ACCESS_KEY=$(aws configure get aws_secret_access_key 2>/dev/null || true)
  export AWS_SESSION_TOKEN=$(aws configure get aws_session_token 2>/dev/null || true)
fi

# Exporta regiao padrao para o aws cli no WSL
export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}"

echo "=========================================================="
echo " Inicio do Deploy Automatizado via Ansible (SGPJ)"
echo "=========================================================="

ansible-playbook -i inventories/production.ini playbooks/site.yml

echo "=========================================================="
echo " Deploy via Ansible concluido com sucesso!"
echo "=========================================================="
