#!/usr/bin/env bash
set -euo pipefail

# CONFIGURAÇÕES

APP_A_IP="98.94.22.209"
APP_B_IP="34.207.115.38"

SSH_USER="ubuntu"
SSH_KEY="$HOME/Key-All.pem"

HTML_A="./a.html"
HTML_B="./b.html"

# PATHS

NGINX_CONF="/mnt/efs-sgpj/volumes/nginx/conf/default.conf"
NGINX_CONF_BACKUP="/mnt/efs-sgpj/volumes/nginx/conf/default.conf.ab-backup"

HTML_DIR="/mnt/efs-sgpj/volumes/nginx/html"

# SSH

SSH_OPTS=(
  -i "$SSH_KEY"
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o ConnectTimeout=10
)

# FUNÇÕES AUXILIARES

step() {
  echo
  echo "=================================================="
  echo "$1"
  echo "=================================================="
}

validate_file() {
  local FILE="$1"

  if [[ ! -f "$FILE" ]]; then
    echo "[ERRO] Arquivo não encontrado: $FILE"
    exit 1
  fi
}

remote_exec() {
  local IP="$1"
  shift

  ssh "${SSH_OPTS[@]}" "$SSH_USER@$IP" "$@"
}

send_file() {
  local IP="$1"
  local SRC="$2"
  local DEST="$3"

  scp "${SSH_OPTS[@]}" "$SRC" "$SSH_USER@$IP:$DEST"
}

# VALIDAÇÕES

validate_file "$SSH_KEY"
validate_file "$HTML_A"
validate_file "$HTML_B"

# DESCOBRE HOSTNAMES

step "[1/7] Descobrindo hostname dos containers"

HOST_A=$(remote_exec "$APP_A_IP" "sudo docker exec nginx hostname")
HOST_B=$(remote_exec "$APP_B_IP" "sudo docker exec nginx hostname")

# Remove CR/LF extras para evitar quebrar a diretiva map do Nginx.
HOST_A="$(echo "$HOST_A" | tr -d '\r\n')"
HOST_B="$(echo "$HOST_B" | tr -d '\r\n')"

echo "APP A -> $HOST_A"
echo "APP B -> $HOST_B"

# ENVIA HTMLS

step "[2/7] Enviando arquivos HTML"

send_file "$APP_A_IP" "$HTML_A" "/tmp/a.html"
send_file "$APP_A_IP" "$HTML_B" "/tmp/b.html"

# MOVE PARA O EFS

step "[3/7] Publicando HTMLs no EFS"

remote_exec "$APP_A_IP" "
  sudo mv /tmp/a.html $HTML_DIR/a.html &&
  sudo mv /tmp/b.html $HTML_DIR/b.html
"

# BACKUP DO NGINX

step "[4/7] Backup da configuração atual"

remote_exec "$APP_A_IP" "
  if [ ! -f $NGINX_CONF_BACKUP ]; then
    sudo cp $NGINX_CONF $NGINX_CONF_BACKUP
  fi
"

# CONFIGURAÇÃO A/B

step "[5/7] Aplicando configuração A/B"

remote_exec "$APP_A_IP" "cat <<'EOF' | sudo tee $NGINX_CONF > /dev/null

map \$hostname \$ab_page {
    default      /a.html;
    $HOST_A      /a.html;
    $HOST_B      /b.html;
}

server {
    listen 80;
    server_name _;

    root /usr/share/nginx/html;
    index index.html;

    location = / {
        add_header X-App-Host \$hostname always;
        try_files \$ab_page =404;
    }

    location / {
        add_header X-App-Host \$hostname always;
        try_files \$uri \$uri/ =404;
    }
}

EOF"

# VALIDA NGINX

step "[6/7] Validando configuração"

remote_exec "$APP_A_IP" "sudo docker exec nginx nginx -t"
remote_exec "$APP_B_IP" "sudo docker exec nginx nginx -t"

# RESTART

step "[7/7] Reiniciando containers"

remote_exec "$APP_A_IP" "sudo docker restart nginx >/dev/null"
remote_exec "$APP_B_IP" "sudo docker restart nginx >/dev/null"

echo "Containers reiniciados com sucesso."

# TESTE

step "Teste local das aplicações"

echo "APP A ($HOST_A)"
remote_exec "$APP_A_IP" "curl -s http://localhost | head -n 5"

echo
echo "APP B ($HOST_B)"
remote_exec "$APP_B_IP" "curl -s http://localhost | head -n 5"

# FINALIZAÇÃO

step "Teste A/B aplicado com sucesso"

echo "Resultado:"
echo " - $HOST_A -> /a.html"
echo " - $HOST_B -> /b.html"

echo
echo "Rollback:"
echo

echo "APP A:"
echo "ssh ${SSH_OPTS[*]} $SSH_USER@$APP_A_IP 'sudo cp $NGINX_CONF_BACKUP $NGINX_CONF && sudo docker restart nginx >/dev/null'"

echo
echo "APP B:"
echo "ssh ${SSH_OPTS[*]} $SSH_USER@$APP_B_IP 'sudo docker restart nginx >/dev/null'"