#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------------------------
# deploy.sh -- Build completo + Push para ECR + Atualizacao via Docker Compose
#
# USO SIMPLES (recomendado):
#   ./deploy.sh             build + deploy frontend, backend E agent
#   ./deploy.sh all         igual ao de cima
#   ./deploy.sh frontend    so o frontend
#   ./deploy.sh backend     so o backend
#   ./deploy.sh agent       so o agente MarIA
#
# Os caminhos do Frontend e Backend ja estao configurados abaixo.
# Nao e necessario passar nenhum argumento extra.
#
# PRE-REQUISITO -- Cole as credenciais do AWS Academy no terminal antes de rodar:
#   export AWS_ACCESS_KEY_ID=...
#   export AWS_SECRET_ACCESS_KEY=...
#   export AWS_SESSION_TOKEN=...
#
# ORDEM DE USO:
#
#   1 vez (infraestrutura ainda nao existe):
#     a) terraform apply -target=aws_ecr_repository.frontend \
#                        -target=aws_ecr_repository.backend \
#                        -target=aws_ecr_lifecycle_policy.frontend \
#                        -target=aws_ecr_lifecycle_policy.backend \
#                        --auto-approve
#         SO NA PRIMEIRA VEZ! Cria os repos ECR antes de subir as imagens.
#
#     b) ./deploy.sh      build + push das imagens para o ECR
#
#     c) terraform apply --auto-approve
#         sobe EC2s + configura Docker Compose + faz deploy via Ansible
#
#   Atualizacoes (infra ja no ar -- uso do dia a dia):
#     ./deploy.sh         build + push + roda Ansible para atualizar
# ------------------------------------------------------------------------------

# -- Cores para output ---------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
info()    { echo -e "${BLUE}-${NC} $*"; }
success() { echo -e "   ${GREEN}-${NC} $*"; }
warn()    { echo -e "   ${YELLOW}- ${NC} $*"; }
error()   { echo -e "${RED}-${NC} $*"; exit 1; }

# -- Caminhos dos projetos (fixos -- altere so se mover as pastas) --------------
DEFAULT_FRONTEND_PATH="/mnt/c/Users/compu/OneDrive - SPTech School/GitHub/Grupo06/Frontend"
DEFAULT_BACKEND_PATH="/mnt/c/Users/compu/OneDrive - SPTech School/GitHub/Grupo06/Backend"
DEFAULT_AGENT_PATH="/mnt/c/Users/compu/OneDrive - SPTech School/GitHub/Grupo06/Agent-Backend"

# -- Parametros ----------------------------------------------------------------
SERVICE="${1:-all}"
DEPLOY_FRONTEND=false
DEPLOY_BACKEND=false
DEPLOY_AGENT=false
FRONTEND_PATH=""
BACKEND_PATH=""
AGENT_PATH=""

case "$SERVICE" in
  all)
    DEPLOY_FRONTEND=true
    DEPLOY_BACKEND=true
    DEPLOY_AGENT=true
    FRONTEND_PATH="${2:-$DEFAULT_FRONTEND_PATH}"
    BACKEND_PATH="${3:-$DEFAULT_BACKEND_PATH}"
    AGENT_PATH="${4:-$DEFAULT_AGENT_PATH}"
    ;;
  frontend)
    DEPLOY_FRONTEND=true
    FRONTEND_PATH="${2:-$DEFAULT_FRONTEND_PATH}"
    ;;
  backend)
    DEPLOY_BACKEND=true
    BACKEND_PATH="${2:-$DEFAULT_BACKEND_PATH}"
    ;;
  agent)
    DEPLOY_AGENT=true
    AGENT_PATH="${2:-$DEFAULT_AGENT_PATH}"
    ;;
  db)
    # Re-provisiona o banco via Ansible (atualiza schema.sql ou configuracoes do MySQL)
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    ANSIBLE_DIR="$SCRIPT_DIR/../ansible"
    INVENTORY="$ANSIBLE_DIR/inventories/production.ini"
    [[ ! -f "$INVENTORY" ]] && error "Inventario nao encontrado. Execute terraform apply primeiro."
    info "Re-provisionando banco de dados MySQL via Ansible..."
    cd "$ANSIBLE_DIR"
    ansible-playbook -i inventories/production.ini playbooks/db.yml
    success "Banco de dados re-provisionado com sucesso!"
    echo ""
    echo "  -  Para atualizar so o schema.sql, edite:"
    echo "  ansible/playbooks/roles/db/files/schema.sql"
    echo ""
    exit 0
    ;;
  *)
    echo ""
    echo "Uso:"
    echo "  $0               deploys frontend + backend + agent (padrao: all)"
    echo "  $0 all           deploys frontend + backend + agent"
    echo "  $0 frontend      so o frontend"
    echo "  $0 backend       so o backend"
    echo "  $0 agent         so o agente MarIA"
    echo "  $0 db            re-provisiona o banco via Ansible"
    echo ""
    error "Servico invalido: '$SERVICE'. Use: all | frontend | backend | agent | db"
    ;;
esac

# Validar caminhos
if $DEPLOY_FRONTEND && [[ ! -d "$FRONTEND_PATH" ]]; then
  error "Diretorio do frontend nao encontrado: $FRONTEND_PATH"
fi
if $DEPLOY_BACKEND && [[ ! -d "$BACKEND_PATH" ]]; then
  error "Diretorio do backend nao encontrado: $BACKEND_PATH"
fi
if $DEPLOY_AGENT && [[ ! -d "$AGENT_PATH" ]]; then
  error "Diretorio do agente nao encontrado: $AGENT_PATH"
fi

# -- Verificar dependencias (com suporte a Windows executado via WSL/Git Bash) --
find_tool() {
  local tool="$1"
  if command -v "$tool" &>/dev/null; then
    echo "$tool"
  elif command -v "${tool}.exe" &>/dev/null; then
    echo "${tool}.exe"
  elif command -v "${tool}.cmd" &>/dev/null; then
    echo "${tool}.cmd"
  elif [[ "$tool" == "aws" && -f "/mnt/c/Program Files/Amazon/AWSCLIV2/aws.exe" ]]; then
    echo "/mnt/c/Program Files/Amazon/AWSCLIV2/aws.exe"
  else
    echo ""
  fi
}

DOCKER_BIN=$(find_tool docker)
AWS_BIN=$(find_tool aws)
NPM_BIN=$(find_tool npm)
MVN_BIN=$(find_tool mvn)
if [[ -z "$MVN_BIN" && -f "$BACKEND_PATH/mvnw" ]]; then
  MVN_BIN="$BACKEND_PATH/mvnw"
elif [[ -z "$MVN_BIN" && -f "$BACKEND_PATH/mvnw.cmd" ]]; then
  MVN_BIN="$BACKEND_PATH/mvnw.cmd"
fi

[[ -z "$DOCKER_BIN" ]] && error "Docker nao encontrado. Instale o Docker ou ative o Docker Desktop."
[[ -z "$AWS_BIN" ]]    && error "AWS CLI nao encontrado. Instale o AWS CLI ou execute pelo PowerShell via: .\deploy.ps1 all"

docker() { "$DOCKER_BIN" "$@"; }
aws()    { "$AWS_BIN" "$@"; }

if $DEPLOY_FRONTEND; then
  if [[ -z "$NPM_BIN" ]]; then
    if [[ -f "$FRONTEND_PATH/dist/index.html" ]]; then
      warn "npm nao encontrado, mas detectada pasta dist/ existente. Reaproveitando build existente do Frontend."
      NPM_BIN="SKIP"
    else
      error "npm nao encontrado e nenhuma pasta dist/ existente. Instale o Node.js no WSL ou execute pelo PowerShell via: .\deploy.ps1 all"
    fi
  fi
  npm() {
    if [[ "$NPM_BIN" == "SKIP" ]]; then
      info "Reaproveitando build existente em dist/..."
    else
      "$NPM_BIN" "$@"
    fi
  }
fi
if $DEPLOY_BACKEND; then
  if [[ -z "$MVN_BIN" ]]; then
    # Verifica se ja existe um JAR compilado no target/
    if compgen -G "$BACKEND_PATH/target/*.jar" > /dev/null; then
      warn "Maven nao encontrado, mas detectado JAR existente em target/. O build usara o JAR existente."
      MVN_BIN="SKIP"
    else
      error "Maven nao encontrado e nenhum JAR em target/. Instale o Maven ou execute pelo PowerShell via: .\deploy.ps1 all"
    fi
  fi
  mvn() {
    if [[ "$MVN_BIN" == "SKIP" ]]; then
      info "Reaproveitando JAR existente em target/..."
    else
      "$MVN_BIN" "$@"
    fi
  }
fi

# -- Verificar credenciais AWS -------------------------------------------------
info "Verificando credenciais AWS..."
CALLER_IDENTITY=$(aws sts get-caller-identity --output json 2>/dev/null) || {
  echo ""
  echo "  As credenciais AWS nao estao configuradas ou expiraram."
  echo "  Cole as credenciais do AWS Academy no terminal antes de rodar o script:"
  echo ""
  echo "    export AWS_ACCESS_KEY_ID=..."
  echo "    export AWS_SECRET_ACCESS_KEY=..."
  echo "    export AWS_SESSION_TOKEN=..."
  echo ""
  error "Credenciais AWS invalidas ou expiradas."
}
ACCOUNT_ID=$(echo "$CALLER_IDENTITY" | grep -oP '"Account":\s*"\K[0-9]+' || echo "")
success "Credenciais AWS validas (Conta: $ACCOUNT_ID)"

# -- Detectar configuracoes geradas pelo Terraform / Ansible -------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ALL_VARS="$SCRIPT_DIR/../ansible/inventories/group_vars/all.yml"
INVENTORY="$SCRIPT_DIR/../ansible/inventories/production.ini"

AWS_REGION=""
ECR_REGISTRY=""

if [[ -f "$ALL_VARS" ]]; then
  AWS_REGION=$(grep "^aws_region:" "$ALL_VARS" 2>/dev/null | awk '{print $2}' | tr -d '"' || true)
  ECR_REGISTRY=$(grep "^ecr_registry_url:" "$ALL_VARS" 2>/dev/null | awk '{print $2}' | tr -d '"' || true)
fi

# Fallback automatico: se all.yml ainda nao existir (1 execucao antes do cluster EC2),
# detecta a regiao e o repositorio ECR diretamente da conta AWS:
if [[ -z "$AWS_REGION" ]]; then
  AWS_REGION="${AWS_DEFAULT_REGION:-$(aws configure get region 2>/dev/null || echo 'us-east-1')}"
fi

if [[ -z "$ECR_REGISTRY" ]]; then
  if [[ -n "$ACCOUNT_ID" ]]; then
    ECR_REGISTRY="${ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
  else
    error "Nao foi possivel determinar o ECR Registry. Execute o terraform apply inicial primeiro."
  fi
fi

ECR_FRONTEND_REPO="${ECR_REGISTRY}/sgpj-frontend"
ECR_BACKEND_REPO="${ECR_REGISTRY}/sgpj-backend"
ECR_AGENT_REPO="${ECR_REGISTRY}/sgpj-agent"

# -- Banner --------------------------------------------------------------------
echo ""
echo "----------------------------------------------------------"
echo "   SGPJ Deploy -- Build + ECR + Docker Compose"
echo "----------------------------------------------------------"
$DEPLOY_FRONTEND && echo "  Frontend    : $FRONTEND_PATH"
$DEPLOY_BACKEND  && echo "  Backend     : $BACKEND_PATH"
$DEPLOY_AGENT    && echo "  Agent       : $AGENT_PATH"
echo "  ECR         : $ECR_REGISTRY"
echo "  Regiao AWS  : $AWS_REGION"
echo "----------------------------------------------------------"
echo ""

STEP=0
next_step() { STEP=$((STEP + 1)); info "[$STEP] $*"; }

# --------------------------------------------------------------
# FRONTEND
# --------------------------------------------------------------
if $DEPLOY_FRONTEND; then

  # -- Passo: npm run build ------------------------------------
  next_step "Gerando build do Frontend (npm run build)..."
  cd "$FRONTEND_PATH"
  npm ci --silent
  npm run build
  [[ -d "$FRONTEND_PATH/dist" ]] || error "dist/ nao foi gerado. Verifique erros no npm run build."
  success "dist/ gerado em $FRONTEND_PATH/dist"

  # -- Passo: docker build -------------------------------------
  next_step "Construindo imagem Docker do Frontend..."
  docker build -t "sgpj-frontend:latest" "$FRONTEND_PATH"
  success "Imagem sgpj-frontend:latest construida"

  # -- Passo: tag ECR ------------------------------------------
  docker tag "sgpj-frontend:latest" "${ECR_FRONTEND_REPO}:latest"
fi

# --------------------------------------------------------------
# BACKEND
# --------------------------------------------------------------
if $DEPLOY_BACKEND; then

  # -- Passo: mvn package --------------------------------------
  next_step "Gerando JAR do Backend (mvn package -DskipTests)..."
  cd "$BACKEND_PATH"
  mvn package -DskipTests --batch-mode -q
  JAR_FILE=$(ls "$BACKEND_PATH"/target/*.jar 2>/dev/null | grep -v "original" | head -1 || true)
  [[ -n "$JAR_FILE" ]] || error "JAR nao encontrado em target/. Verifique erros no mvn package."
  success "JAR gerado: $(basename "$JAR_FILE")"

  # -- Passo: docker build -------------------------------------
  next_step "Construindo imagem Docker do Backend..."
  docker build -t "sgpj-backend:latest" "$BACKEND_PATH"
  success "Imagem sgpj-backend:latest construida"

  # -- Passo: tag ECR ------------------------------------------
  docker tag "sgpj-backend:latest" "${ECR_BACKEND_REPO}:latest"
fi

# --------------------------------------------------------------
# AGENTE (MarIA)
# --------------------------------------------------------------
if $DEPLOY_AGENT; then
  next_step "Construindo imagem Docker do Agente MarIA..."
  docker build --platform linux/amd64 -t "sgpj-agent:latest" "$AGENT_PATH"
  success "Imagem sgpj-agent:latest construida"

  docker tag "sgpj-agent:latest" "${ECR_AGENT_REPO}:latest"
fi

# --------------------------------------------------------------
# LOGIN ECR (1x para todas as imagens)
# --------------------------------------------------------------
next_step "Autenticando no Amazon ECR..."
aws ecr get-login-password --region "$AWS_REGION" \
  | docker login --username AWS --password-stdin "$ECR_REGISTRY"
success "Login no ECR concluido"

# --------------------------------------------------------------
# PUSH PARA ECR
# --------------------------------------------------------------
if $DEPLOY_FRONTEND; then
  next_step "Enviando imagem do Frontend para o ECR..."
  docker push "${ECR_FRONTEND_REPO}:latest"
  success "sgpj-frontend:latest disponivel no ECR"
fi

if $DEPLOY_BACKEND; then
  next_step "Enviando imagem do Backend para o ECR..."
  docker push "${ECR_BACKEND_REPO}:latest"
  success "sgpj-backend:latest disponivel no ECR"
fi

if $DEPLOY_AGENT; then
  next_step "Enviando imagem do Agente para o ECR..."
  docker push "${ECR_AGENT_REPO}:latest"
  success "sgpj-agent:latest disponivel no ECR"
fi

# --------------------------------------------------------------
# FINALIZACAO
# --------------------------------------------------------------
warn "As imagens ja estao no ECR!"
warn "Agora rode o Ansible para atualizar as EC2s: ./run_ansible.sh"

echo ""
echo "----------------------------------------------------------"
echo "  - Deploy concluido com sucesso!"
echo "----------------------------------------------------------"
echo ""
