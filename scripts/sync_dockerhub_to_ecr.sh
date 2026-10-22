#!/usr/bin/env bash
set -e

# ──────────────────────────────────────────────────────────────────────────────
# sync_dockerhub_to_ecr.sh
# Sincroniza as imagens mais recentes do Docker Hub para o Amazon ECR
#
# Uso:
#   ./sync_dockerhub_to_ecr.sh <AWS_REGION> <ECR_FRONTEND_URL> <ECR_BACKEND_URL> [DOCKER_FRONTEND_HUB] [DOCKER_BACKEND_HUB]
# ──────────────────────────────────────────────────────────────────────────────

AWS_REGION="${1:-us-east-1}"
ECR_FRONTEND_URL="$2"
ECR_BACKEND_URL="$3"
DOCKER_FRONTEND_HUB="${4:-lpamorim/sgpj-frontend:latest}"
DOCKER_BACKEND_HUB="${5:-lpamorim/sgpj-backend:latest}"

if [ -z "$ECR_FRONTEND_URL" ] || [ -z "$ECR_BACKEND_URL" ]; then
    echo "ERRO: ECR_FRONTEND_URL e ECR_BACKEND_URL são obrigatórios."
    echo "Uso: $0 <AWS_REGION> <ECR_FRONTEND_URL> <ECR_BACKEND_URL> [DOCKER_FRONTEND_HUB] [DOCKER_BACKEND_HUB]"
    exit 1
fi

echo "=========================================================="
echo " Sincronizando imagens: Docker Hub -> Amazon ECR"
echo " Regiao AWS        : $AWS_REGION"
echo " Frontend Hub      : $DOCKER_FRONTEND_HUB"
echo " Frontend ECR      : $ECR_FRONTEND_URL:latest"
echo " Backend Hub       : $DOCKER_BACKEND_HUB"
echo " Backend ECR       : $ECR_BACKEND_URL:latest"
echo "=========================================================="

# 1. Puxar as versoes mais recentes do Docker Hub
echo "[1/4] Baixando versoes mais recentes do Docker Hub..."
docker pull "$DOCKER_FRONTEND_HUB"
docker pull "$DOCKER_BACKEND_HUB"

# 2. Autenticar no Amazon ECR
echo "[2/4] Autenticando no Amazon ECR..."
ECR_REGISTRY=$(echo "$ECR_FRONTEND_URL" | cut -d'/' -f1)
aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$ECR_REGISTRY"

# 3. Criar tags do ECR
echo "[3/4] Aplicando tags para o Amazon ECR..."
docker tag "$DOCKER_FRONTEND_HUB" "${ECR_FRONTEND_URL}:latest"
docker tag "$DOCKER_BACKEND_HUB" "${ECR_BACKEND_URL}:latest"

# 4. Fazer push para o Amazon ECR
echo "[4/4] Enviando imagens para o Amazon ECR..."
docker push "${ECR_FRONTEND_URL}:latest"
docker push "${ECR_BACKEND_URL}:latest"

echo "=========================================================="
echo " Sincronizacao com o Amazon ECR concluida com sucesso!"
echo "=========================================================="
