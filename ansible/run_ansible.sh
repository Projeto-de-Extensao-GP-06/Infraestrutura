#!/usr/bin/env bash
set -e

# Navega para o diretorio do script (infra/ansible)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

export ANSIBLE_CONFIG=./ansible.cfg

echo "=========================================================="
echo " Início do Deploy Automatizado via Ansible (SGPJ)"
echo "=========================================================="

ansible-playbook -i inventories/production.ini playbooks/site.yml

echo "=========================================================="
echo " Deploy via Ansible concluído com sucesso!"
echo "=========================================================="
