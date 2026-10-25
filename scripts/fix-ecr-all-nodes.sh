#!/bin/bash
# fix-ecr-all-nodes.sh
# Faz login ECR em todos os nodes do Swarm e re-deploya a stack

set -e
KEY=~/.ssh/vockey.pem
REGION=us-east-1
ACCOUNT=487375662162
ECR_URL="${ACCOUNT}.dkr.ecr.${REGION}.amazonaws.com"
MANAGER=18.232.101.98

WORKERS=(
  "3.239.192.47"    # app-b
  "10.0.3.173"      # backend-a (privado, acessa via manager)
  "10.0.4.238"      # backend-b (privado, acessa via manager)
)

ECR_LOGIN_CMD="aws ecr get-login-password --region ${REGION} | docker login --username AWS --password-stdin ${ECR_URL}"

echo "=== [1/3] Login ECR no Manager (${MANAGER}) ==="
ssh -i $KEY -o StrictHostKeyChecking=no ubuntu@${MANAGER} "$ECR_LOGIN_CMD"

echo "=== [2/3] Login ECR no Worker app-b (${WORKERS[0]}) ==="
ssh -i $KEY -o StrictHostKeyChecking=no ubuntu@${WORKERS[0]} "$ECR_LOGIN_CMD"

echo "=== [3/3] Login ECR nos Workers backend via Manager (jump host) ==="
ssh -i $KEY -o StrictHostKeyChecking=no -J ubuntu@${MANAGER} ubuntu@${WORKERS[1]} "$ECR_LOGIN_CMD"
ssh -i $KEY -o StrictHostKeyChecking=no -J ubuntu@${MANAGER} ubuntu@${WORKERS[2]} "$ECR_LOGIN_CMD"

echo "=== [4/4] Re-deploy da stack no Manager ==="
ssh -i $KEY -o StrictHostKeyChecking=no ubuntu@${MANAGER} \
  "docker stack deploy --with-registry-auth --compose-file /opt/swarm/stack.yml sgpj"

echo ""
echo "=== Aguardando containers subirem (30s) ==="
sleep 30

echo "=== Status da stack ==="
ssh -i $KEY -o StrictHostKeyChecking=no ubuntu@${MANAGER} "docker service ls"
