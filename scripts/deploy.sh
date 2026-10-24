#!/usr/bin/env bash
set -euo pipefail

# ──────────────────────────────────────────────────────────────────────────────
# deploy.sh — Build completo + Push para ECR + Atualização no Docker Swarm
#
# USO SIMPLES (recomendado):
#   ./deploy.sh            → build + deploy frontend E backend
#   ./deploy.sh all        → igual ao de cima
#   ./deploy.sh frontend   → só o frontend
#   ./deploy.sh backend    → só o backend
#
# Os caminhos do Frontend e Backend já estão configurados abaixo.
# Não é necessário passar nenhum argumento extra.
#
# PRÉ-REQUISITO — Cole as credenciais do AWS Academy no terminal antes de rodar:
#   export AWS_ACCESS_KEY_ID=...
#   export AWS_SECRET_ACCESS_KEY=...
#   export AWS_SESSION_TOKEN=...
#
# ORDEM DE USO:
#
#   1ª vez (infraestrutura ainda não existe):
#     a) terraform apply -target=aws_ecr_repository.frontend \
#                        -target=aws_ecr_repository.backend \
#                        -target=aws_ecr_lifecycle_policy.frontend \
#                        -target=aws_ecr_lifecycle_policy.backend \
#                        --auto-approve
#        ↑ SÓ NA PRIMEIRA VEZ! Cria os repos ECR antes de subir as imagens.
#
#     b) ./deploy.sh     ← build + push das imagens para o ECR
#
#     c) terraform apply --auto-approve
#        ← sobe EC2s + inicializa Swarm + faz deploy da stack do ECR
#
#   Atualizações (infra já no ar — uso do dia a dia):
#     ./deploy.sh        ← build + push + rolling update automático no Swarm
# ──────────────────────────────────────────────────────────────────────────────

# ── Cores para output ─────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}▶${NC} $*"; }
success() { echo -e "   ${GREEN}✅${NC} $*"; }
warn()    { echo -e "   ${YELLOW}⚠️ ${NC} $*"; }
error()   { echo -e "${RED}❌${NC} $*"; exit 1; }

# ── Caminhos dos projetos (fixos — altere só se mover as pastas) ──────────────
DEFAULT_FRONTEND_PATH="/mnt/c/Users/compu/OneDrive - SPTech School/GitHub/Grupo06/Frontend"
DEFAULT_BACKEND_PATH="/mnt/c/Users/compu/OneDrive - SPTech School/GitHub/Grupo06/Backend"

# ── Parâmetros ────────────────────────────────────────────────────────────────
SERVICE="${1:-all}"
DEPLOY_FRONTEND=false
DEPLOY_BACKEND=false
FRONTEND_PATH=""
BACKEND_PATH=""

case "$SERVICE" in
  all)
    DEPLOY_FRONTEND=true
    DEPLOY_BACKEND=true
    FRONTEND_PATH="${2:-$DEFAULT_FRONTEND_PATH}"
    BACKEND_PATH="${3:-$DEFAULT_BACKEND_PATH}"
    ;;
  frontend)
    DEPLOY_FRONTEND=true
    FRONTEND_PATH="${2:-$DEFAULT_FRONTEND_PATH}"
    ;;
  backend)
    DEPLOY_BACKEND=true
    BACKEND_PATH="${2:-$DEFAULT_BACKEND_PATH}"
    ;;
  *)
    echo ""
    echo "Uso:"
    echo "  $0              → deploys frontend + backend (padrão: all)"
    echo "  $0 all          → deploys frontend + backend"
    echo "  $0 frontend     → só o frontend"
    echo "  $0 backend      → só o backend"
    echo ""
    error "Serviço inválido: '$SERVICE'. Use: all | frontend | backend"
    ;;
esac

# Validar caminhos
if $DEPLOY_FRONTEND && [[ ! -d "$FRONTEND_PATH" ]]; then
  error "Diretório do frontend não encontrado: $FRONTEND_PATH"
fi
if $DEPLOY_BACKEND && [[ ! -d "$BACKEND_PATH" ]]; then
  error "Diretório do backend não encontrado: $BACKEND_PATH"
fi

# ── Detectar configurações geradas pelo Terraform ─────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALL_VARS="$SCRIPT_DIR/../ansible/inventories/group_vars/all.yml"
INVENTORY="$SCRIPT_DIR/../ansible/inventories/production.ini"

if [[ ! -f "$ALL_VARS" ]]; then
  error "Inventário não encontrado: $ALL_VARS\n   Execute primeiro:\n   terraform apply -target=aws_ecr_repository.frontend -target=aws_ecr_repository.backend --auto-approve"
fi

AWS_REGION=$(grep "^aws_region:"       "$ALL_VARS" | awk '{print $2}' | tr -d '"')
ECR_REGISTRY=$(grep "^ecr_registry_url:" "$ALL_VARS" | awk '{print $2}' | tr -d '"')
ECR_FRONTEND_REPO="${ECR_REGISTRY}/sgpj-frontend"
ECR_BACKEND_REPO="${ECR_REGISTRY}/sgpj-backend"

# IP do Manager (ec2-app-a) e chave SSH
MANAGER_IP=$(grep -A5 "\[app\]" "$INVENTORY" 2>/dev/null | grep "ansible_host=" | head -1 | grep -oP "ansible_host=\K[0-9.]+" || true)
KEY_FILE=$(grep "ansible_ssh_private_key_file=" "$INVENTORY" 2>/dev/null | head -1 | grep -oP "ansible_ssh_private_key_file=\K\S+" || true)

# ── Verificar dependências ────────────────────────────────────────────────────
command -v docker &>/dev/null || error "Docker não encontrado. Instale o Docker no WSL."
command -v aws    &>/dev/null || error "AWS CLI não encontrado. Instale com: pip install awscli"

if $DEPLOY_FRONTEND; then
  command -v npm  &>/dev/null || error "npm não encontrado. Instale o Node.js no WSL: sudo apt install nodejs npm"
fi
if $DEPLOY_BACKEND; then
  command -v mvn  &>/dev/null || error "Maven não encontrado. Instale com: sudo apt install maven"
fi

# ── Verificar credenciais AWS ─────────────────────────────────────────────────
info "Verificando credenciais AWS..."
aws sts get-caller-identity &>/dev/null || {
  echo ""
  echo "  As credenciais AWS não estão configuradas ou expiraram."
  echo "  Cole as credenciais do AWS Academy no terminal antes de rodar o script:"
  echo ""
  echo "    export AWS_ACCESS_KEY_ID=..."
  echo "    export AWS_SECRET_ACCESS_KEY=..."
  echo "    export AWS_SESSION_TOKEN=..."
  echo ""
  error "Credenciais AWS inválidas ou expiradas."
}
success "Credenciais AWS válidas"

# ── Banner ────────────────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════════════"
echo "  🚀 SGPJ Deploy — Build + ECR + Docker Swarm"
echo "══════════════════════════════════════════════════════════"
$DEPLOY_FRONTEND && echo "  Frontend    : $FRONTEND_PATH"
$DEPLOY_BACKEND  && echo "  Backend     : $BACKEND_PATH"
echo "  ECR         : $ECR_REGISTRY"
echo "  Região AWS  : $AWS_REGION"
[[ -n "$MANAGER_IP" ]] && echo "  Manager IP  : $MANAGER_IP" || echo "  Manager IP  : (Swarm não detectado — apenas push ECR)"
echo "══════════════════════════════════════════════════════════"
echo ""

STEP=0
total_steps=0
$DEPLOY_FRONTEND && total_steps=$((total_steps + 3))  # build + docker build + push
$DEPLOY_BACKEND  && total_steps=$((total_steps + 3))
total_steps=$((total_steps + 1))  # login ECR (1x)
[[ -n "$MANAGER_IP" ]] && total_steps=$((total_steps + 1))  # swarm update

next_step() { STEP=$((STEP + 1)); info "[$STEP/?] $*"; }

# ══════════════════════════════════════════════════════════════
# FRONTEND
# ══════════════════════════════════════════════════════════════
if $DEPLOY_FRONTEND; then

  # ── Passo: npm run build ────────────────────────────────────
  next_step "Gerando build do Frontend (npm run build)..."
  cd "$FRONTEND_PATH"
  npm ci --silent
  npm run build
  [[ -d "$FRONTEND_PATH/dist" ]] || error "dist/ não foi gerado. Verifique erros no npm run build."
  success "dist/ gerado em $FRONTEND_PATH/dist"

  # ── Passo: docker build ─────────────────────────────────────
  next_step "Construindo imagem Docker do Frontend..."
  docker build -t "sgpj-frontend:latest" "$FRONTEND_PATH"
  success "Imagem sgpj-frontend:latest construída"

  # ── Passo: tag ECR ──────────────────────────────────────────
  docker tag "sgpj-frontend:latest" "${ECR_FRONTEND_REPO}:latest"
fi

# ══════════════════════════════════════════════════════════════
# BACKEND
# ══════════════════════════════════════════════════════════════
if $DEPLOY_BACKEND; then

  # ── Passo: mvn package ──────────────────────────────────────
  next_step "Gerando JAR do Backend (mvn package -DskipTests)..."
  cd "$BACKEND_PATH"
  mvn package -DskipTests --batch-mode -q
  JAR_FILE=$(ls "$BACKEND_PATH"/target/*.jar 2>/dev/null | grep -v "original" | head -1 || true)
  [[ -n "$JAR_FILE" ]] || error "JAR não encontrado em target/. Verifique erros no mvn package."
  success "JAR gerado: $(basename "$JAR_FILE")"

  # ── Passo: docker build ─────────────────────────────────────
  next_step "Construindo imagem Docker do Backend..."
  docker build -t "sgpj-backend:latest" "$BACKEND_PATH"
  success "Imagem sgpj-backend:latest construída"

  # ── Passo: tag ECR ──────────────────────────────────────────
  docker tag "sgpj-backend:latest" "${ECR_BACKEND_REPO}:latest"
fi

# ══════════════════════════════════════════════════════════════
# LOGIN ECR (1x para ambas as imagens)
# ══════════════════════════════════════════════════════════════
next_step "Autenticando no Amazon ECR..."
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$ECR_REGISTRY"
success "Login no ECR concluído"

# ══════════════════════════════════════════════════════════════
# PUSH PARA ECR
# ══════════════════════════════════════════════════════════════
if $DEPLOY_FRONTEND; then
  next_step "Enviando imagem do Frontend para o ECR..."
  docker push "${ECR_FRONTEND_REPO}:latest"
  success "sgpj-frontend:latest disponível no ECR"
fi

if $DEPLOY_BACKEND; then
  next_step "Enviando imagem do Backend para o ECR..."
  docker push "${ECR_BACKEND_REPO}:latest"
  success "sgpj-backend:latest disponível no ECR"
fi

# ══════════════════════════════════════════════════════════════
# ATUALIZAÇÃO NO SWARM (rolling update) — só se Swarm estiver no ar
# ══════════════════════════════════════════════════════════════
if [[ -n "$MANAGER_IP" ]]; then
  SSH_OPTS="-o StrictHostKeyChecking=no -o ConnectTimeout=10"
  [[ -n "$KEY_FILE" ]] && SSH_OPTS="$SSH_OPTS -i $KEY_FILE"

  # Verifica se o Swarm já está ativo no manager
  SWARM_ACTIVE=$(ssh $SSH_OPTS ubuntu@"$MANAGER_IP" \
    "docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null" || echo "inactive")

  if [[ "$SWARM_ACTIVE" == "active" ]]; then
    next_step "Atualizando serviços no Docker Swarm (rolling update)..."

    if $DEPLOY_FRONTEND; then
      ssh $SSH_OPTS ubuntu@"$MANAGER_IP" \
        "docker service update --image ${ECR_FRONTEND_REPO}:latest --with-registry-auth sgpj_nginx"
      success "sgpj_nginx atualizado (zero-downtime)"
    fi

    if $DEPLOY_BACKEND; then
      ssh $SSH_OPTS ubuntu@"$MANAGER_IP" \
        "docker service update --image ${ECR_BACKEND_REPO}:latest --with-registry-auth sgpj_backend"
      success "sgpj_backend atualizado (zero-downtime)"
    fi

    echo ""
    echo "  Para acompanhar o rolling update:"
    [[ "$DEPLOY_FRONTEND" == "true" ]] && echo "  ssh ubuntu@${MANAGER_IP} 'docker service ps sgpj_nginx'"
    [[ "$DEPLOY_BACKEND"  == "true" ]] && echo "  ssh ubuntu@${MANAGER_IP} 'docker service ps sgpj_backend'"
  else
    warn "Swarm ainda não está ativo no Manager ($MANAGER_IP)."
    warn "As imagens já estão no ECR. Rode 'terraform apply --auto-approve' para subir tudo."
  fi
else
  warn "IP do Manager não detectado no inventário."
  warn "As imagens já estão no ECR. Rode 'terraform apply --auto-approve' para subir tudo."
fi

# ══════════════════════════════════════════════════════════════
echo ""
echo "══════════════════════════════════════════════════════════"
echo "  ✅ Deploy concluído com sucesso!"
echo "══════════════════════════════════════════════════════════"
echo ""
