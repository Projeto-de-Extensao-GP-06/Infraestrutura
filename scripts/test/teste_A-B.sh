#!/usr/bin/env bash
set -euo pipefail

# CONFIGURACOES

APP_A_IP="3.81.108.222"
APP_B_IP="44.193.219.76"

SSH_USER="ubuntu"
SSH_KEY="$HOME/.ssh/Key-All.pem"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FRONTEND_DIST="$SCRIPT_DIR/dist"

# PATHS

NGINX_CONF="/mnt/efs-sgpj/volumes/nginx/conf/default.conf"
NGINX_CONF_BACKUP="/mnt/efs-sgpj/volumes/nginx/conf/default.conf.frontend-backup"
HTML_DIR="/mnt/efs-sgpj/volumes/nginx/html"
ARCHIVE_NAME="frontend-dist.tar.gz"

# SSH

SSH_OPTS=(
  -i "$SSH_KEY"
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o ConnectTimeout=10
)

# FUNCOES AUXILIARES

step() {
  echo
  echo "=================================================="
  echo "$1"
  echo "=================================================="
}

validate_file() {
  local file="$1"

  if [[ ! -f "$file" ]]; then
    echo "[ERRO] Arquivo nao encontrado: $file"
    exit 1
  fi
}

validate_directory() {
  local directory="$1"

  if [[ ! -d "$directory" || ! -f "$directory/index.html" ]]; then
    echo "[ERRO] Diretorio dist invalido (index.html nao encontrado): $directory"
    exit 1
  fi
}

remote_exec() {
  local ip="$1"
  shift

  ssh "${SSH_OPTS[@]}" "$SSH_USER@$ip" "$@"
}

send_file() {
  local ip="$1"
  local source="$2"
  local destination="$3"

  scp "${SSH_OPTS[@]}" "$source" "$SSH_USER@$ip:$destination"
}

# VALIDACOES

validate_file "$SSH_KEY"
validate_directory "$FRONTEND_DIST"

# OpenSSH recusa chaves que podem ser lidas por outros usuarios.
chmod 600 "$SSH_KEY"

# EMPACOTA E PUBLICA O FRONTEND

step "[1/5] Empacotando o frontend"

ARCHIVE_PATH="$(mktemp "${TMPDIR:-/tmp}/$ARCHIVE_NAME.XXXXXX")"
trap 'rm -f "$ARCHIVE_PATH"' EXIT
tar -C "$FRONTEND_DIST" -czf "$ARCHIVE_PATH" .

step "[2/5] Enviando o frontend para o EFS"

send_file "$APP_A_IP" "$ARCHIVE_PATH" "/tmp/$ARCHIVE_NAME"

remote_exec "$APP_A_IP" "
  set -e
  staging_dir=\$(mktemp -d)
  trap 'rm -rf \"\$staging_dir\" /tmp/$ARCHIVE_NAME' EXIT
  tar -xzf /tmp/$ARCHIVE_NAME -C \"\$staging_dir\"
  sudo mkdir -p $HTML_DIR
  sudo find $HTML_DIR -mindepth 1 -maxdepth 1 -exec rm -rf {} +
  sudo cp -a \"\$staging_dir\"/. $HTML_DIR/
"

# CONFIGURA O NGINX

step "[3/5] Aplicando configuracao do Nginx para SPA"

remote_exec "$APP_A_IP" "
  if [ -f $NGINX_CONF ] && [ ! -f $NGINX_CONF_BACKUP ]; then
    sudo cp $NGINX_CONF $NGINX_CONF_BACKUP
  fi
"

remote_exec "$APP_A_IP" "cat <<'EOF' | sudo tee $NGINX_CONF > /dev/null
server {
    listen 80;
    server_name _;

    root /usr/share/nginx/html;
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
EOF"

# VALIDA E REINICIA

step "[4/5] Validando e reiniciando o Nginx"

remote_exec "$APP_A_IP" "sudo docker exec nginx nginx -t"
remote_exec "$APP_B_IP" "sudo docker exec nginx nginx -t"
remote_exec "$APP_A_IP" "sudo docker restart nginx >/dev/null"
remote_exec "$APP_B_IP" "sudo docker restart nginx >/dev/null"

# TESTA AS DUAS INSTANCIAS

step "[5/5] Testando o frontend nas duas instancias"

for ip in "$APP_A_IP" "$APP_B_IP"; do
  echo "Instancia $ip"
  remote_exec "$ip" "curl -fsS --max-time 10 http://localhost/ | grep -q '<div id=\"root\"></div>'"
  remote_exec "$ip" "curl -fsSI --max-time 10 http://localhost/ | head -n 1"
done

step "Frontend publicado com sucesso"

echo "Dist publicado em: $HTML_DIR"
echo "Configuracao anterior salva em: $NGINX_CONF_BACKUP"
echo "Rollback APP A: ssh ${SSH_OPTS[*]} $SSH_USER@$APP_A_IP 'sudo cp $NGINX_CONF_BACKUP $NGINX_CONF && sudo docker restart nginx >/dev/null'"
echo "Rollback APP B: ssh ${SSH_OPTS[*]} $SSH_USER@$APP_B_IP 'sudo docker restart nginx >/dev/null'"
