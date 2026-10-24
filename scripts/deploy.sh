#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# deploy.sh — Deploy manual para o Amazon ECR + Docker Swarm
#
# Uso:
#   ./deploy.sh <SERVICE> <BUILD_CONTEXT_PATH> [TAG]
#
#   SERVICE            : "frontend" ou "backend"
#   BUILD_CONTEXT_PATH : caminho para a pasta com o Dockerfile
#   TAG                : tag da imagem (default: latest)
#
# Exemplos:
#   ./deploy.sh backend /home/user/sgpj-backend
#   ./deploy.sh frontend /home/user/sgpj-frontend v1.2.0
#
# Pré-requisitos:
#   - AWS CLI configurado (aws configure)
#   - Docker instalado e rodando
#   - SSH access ao Swarm Manager (ec2-app-a)
#   - Arquivo de inventário: ../ansible/inventories/production.ini
# ──────────────────────────────────────────────────────────────────────────────

# ── Parâmetros ────────────────────────────────────────────────────────────────
SERVICE="${1:-}"
BUILD_CTX="${2:-}"
TAG="${3:-latest}"

# ── Validações ────────────────────────────────────────────────────────────────
if [[ -z "$SERVICE" || -z "$BUILD_CTX" ]]; then
  echo "❌ Uso: $0 <frontend|backend> <caminho_build_context> [tag]"
  echo "   Exemplos:"
  echo "     $0 backend /home/user/sgpj-backend"
  echo "     $0 frontend /home/user/sgpj-frontend v1.2.0"
  exit 1
fi

if [[ "$SERVICE" != "frontend" && "$SERVICE" != "backend" ]]; then
  echo "❌ SERVICE deve ser 'frontend' ou 'backend'. Recebido: '$SERVICE'"
  exit 1
fi

if [[ ! -d "$BUILD_CTX" ]]; then
  echo "❌ Diretório de build não encontrado: $BUILD_CTX"
  exit 1
fi

# ── Detectar configurações do ambiente ───────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INVENTORY="$SCRIPT_DIR/../ansible/inventories/production.ini"
ALL_VARS="$SCRIPT_DIR/../ansible/inventories/group_vars/all.yml"

if [[ ! -f "$ALL_VARS" ]]; then
  echo "❌ Arquivo de variáveis não encontrado: $ALL_VARS"
  echo "   Execute 'terraform apply' primeiro para gerar os inventários."
  exit 1
fi

# Extrair variáveis do all.yml
AWS_REGION=$(grep "^aws_region:" "$ALL_VARS" | awk '{print $2}' | tr -d '"')
ECR_REGISTRY=$(grep "^ecr_registry_url:" "$ALL_VARS" | awk '{print $2}' | tr -d '"')
ECR_IMAGE=$(grep "^ecr_${SERVICE}_image:" "$ALL_VARS" | awk '{print $2}' | tr -d '"')
ECR_REPO="${ECR_REGISTRY}/sgpj-${SERVICE}"

# Extrair IP do manager do inventário
MANAGER_IP=$(grep -A2 "\[app\]" "$INVENTORY" | grep "ansible_host=" | head -1 | grep -oP "ansible_host=\K[0-9.]+")
KEY_FILE=$(grep "ansible_ssh_private_key_file=" "$INVENTORY" | head -1 | grep -oP "ansible_ssh_private_key_file=\K\S+")

if [[ -z "$MANAGER_IP" ]]; then
  echo "❌ Não foi possível detectar o IP do Swarm Manager no inventário."
  exit 1
fi

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════════════"
echo "  🚀 SGPJ Deploy — Docker Swarm via ECR"
echo "══════════════════════════════════════════════════════════"
echo "  Serviço     : sgpj-${SERVICE}"
echo "  Build ctx   : ${BUILD_CTX}"
echo "  Tag         : ${TAG}"
echo "  ECR repo    : ${ECR_REPO}:${TAG}"
echo "  Manager     : ${MANAGER_IP}"
echo "  Região AWS  : ${AWS_REGION}"
echo "══════════════════════════════════════════════════════════"
echo ""

# ── 1. Build da imagem ────────────────────────────────────────────────────────
echo "▶ [1/5] Buildando imagem local..."
docker build -t "sgpj-${SERVICE}:${TAG}" "$BUILD_CTX"
echo "   ✅ Build concluído"

# ── 2. Tag para ECR ───────────────────────────────────────────────────────────
echo "▶ [2/5] Aplicando tag ECR..."
docker tag "sgpj-${SERVICE}:${TAG}" "${ECR_REPO}:${TAG}"
if [[ "$TAG" != "latest" ]]; then
  docker tag "sgpj-${SERVICE}:${TAG}" "${ECR_REPO}:latest"
fi
echo "   ✅ Tag aplicada: ${ECR_REPO}:${TAG}"

# ── 3. Login no ECR ───────────────────────────────────────────────────────────
echo "▶ [3/5] Autenticando no Amazon ECR..."
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$ECR_REGISTRY"
echo "   ✅ Login no ECR concluído"

# ── 4. Push para ECR ──────────────────────────────────────────────────────────
echo "▶ [4/5] Enviando imagem para o ECR..."
docker push "${ECR_REPO}:${TAG}"
if [[ "$TAG" != "latest" ]]; then
  docker push "${ECR_REPO}:latest"
fi
echo "   ✅ Push concluído"

# ── 5. Atualizar serviço no Swarm (rolling update) ────────────────────────────
echo "▶ [5/5] Atualizando serviço no Docker Swarm (rolling update)..."

SWARM_SERVICE="sgpj_${SERVICE}"
# frontend no swarm se chama "nginx" (conforme a stack)
if [[ "$SERVICE" == "frontend" ]]; then
  SWARM_SERVICE="sgpj_nginx"
fi

SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10"
if [[ -n "$KEY_FILE" ]]; then
  SSH_OPTS="$SSH_OPTS -i $KEY_FILE"
fi

ssh $SSH_OPTS ubuntu@"$MANAGER_IP" \
  "docker service update \
    --image ${ECR_REPO}:${TAG} \
    --with-registry-auth \
    ${SWARM_SERVICE}"

echo "   ✅ Rolling update iniciado"
echo ""
echo "══════════════════════════════════════════════════════════"
echo "  ✅ Deploy concluído com sucesso!"
echo ""
echo "  Para acompanhar o progresso:"
echo "  ssh ubuntu@${MANAGER_IP} 'docker service ps ${SWARM_SERVICE}'"
echo "══════════════════════════════════════════════════════════"
echo ""
