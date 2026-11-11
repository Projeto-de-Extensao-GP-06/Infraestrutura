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

MAX_ATTEMPTS=2
ATTEMPT=1

while [[ $ATTEMPT -le $MAX_ATTEMPTS ]]; do
  echo ""
  echo "[Ansible] Tentativa $ATTEMPT de $MAX_ATTEMPTS..."
  echo ""

  if ansible-playbook -i inventories/production.ini playbooks/site.yml; then
    echo ""
    echo "=========================================================="
    echo " Deploy via Ansible concluido com sucesso! (tentativa $ATTEMPT)"
    echo "=========================================================="
    exit 0
  fi

  EXIT_CODE=$?

  if [[ $ATTEMPT -lt $MAX_ATTEMPTS ]]; then
    echo ""
    echo "[Ansible] Tentativa $ATTEMPT falhou (exit $EXIT_CODE)."
    echo "[Ansible] Aguardando 30s antes de tentar novamente..."
    sleep 30
  fi

  ATTEMPT=$((ATTEMPT + 1))
done

echo ""
echo "[Ansible] ERRO: todas as $MAX_ATTEMPTS tentativas falharam." >&2
exit 1
