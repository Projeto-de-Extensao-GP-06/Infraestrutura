#!/bin/bash
# Sincroniza credenciais ativas da AWS com os Secrets do GitHub
# e dispara o workflow cd.yml para subir as imagens no ECR.
set -euo pipefail

REPOS=(
  "Projeto-de-Extensao-GP-06/Backend"
  "Projeto-de-Extensao-GP-06/Frontend"
  "Projeto-de-Extensao-GP-06/Agent-Backend"
)

echo "--> Verificando credenciais da AWS..."
AWS_KEY=$(aws configure get aws_access_key_id)
AWS_SECRET=$(aws configure get aws_secret_access_key)
AWS_TOKEN=$(aws configure get aws_session_token)

if [ -z "$AWS_KEY" ] || [ -z "$AWS_SECRET" ] || [ -z "$AWS_TOKEN" ]; then
  echo "Erro: Credenciais AWS incompletas. Execute 'aws configure' antes."
  exit 1
fi

for repo in "${REPOS[@]}"; do
  echo "--> Atualizando Secrets em: $repo"
  echo "$AWS_KEY" | gh secret set AWS_ACCESS_KEY_ID --repo "$repo"
  echo "$AWS_SECRET" | gh secret set AWS_SECRET_ACCESS_KEY --repo "$repo"
  echo "$AWS_TOKEN" | gh secret set AWS_SESSION_TOKEN --repo "$repo"

  echo "--> Disparando workflow cd.yml em $repo..."
  gh workflow run cd.yml --repo "$repo" --ref main || true
done

echo "Concluido com sucesso!"