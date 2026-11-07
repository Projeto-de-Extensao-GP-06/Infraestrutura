#!/bin/bash
set -e

echo "=== Teste Lambda Ingestão de Dados Externos ==="

ENDPOINT_URL="http://localhost:4566"
REGION="us-east-1"
AWS_ACCESS_KEY_ID="test"
AWS_SECRET_ACCESS_KEY="test"

export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION=$REGION

# ============================================================
# CRIAR RECURSOS LAMBDA
# ============================================================

create_lambda_resources() {
    echo "=== Criando recursos Lambda ==="

    # Criar bucket externo
    echo "Criando bucket sgpj-external..."
    aws --endpoint-url=$ENDPOINT_URL s3 mb s3://sgpj-external 2>/dev/null || echo "Bucket já existe"

    # Habilitar versionamento
    aws --endpoint-url=$ENDPOINT_URL s3api put-bucket-versioning \
        --bucket sgpj-external \
        --versioning-configuration Status=Enabled

    # Criar IAM Role para Lambda
    echo "Criando IAM Role para Lambda..."
    cat > /tmp/lambda_trust_policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF

    aws --endpoint-url=$ENDPOINT_URL iam create-role \
        --role-name sgpj-lambda-ingestion-role \
        --assume-role-policy-document file:///tmp/lambda_trust_policy.json \
        2>/dev/null || echo "Role já existe"

    # Criar IAM Policy
    cat > /tmp/lambda_policy.json <<'EOF'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:CopyObject"
      ],
      "Resource": [
        "arn:aws:s3:::sgpj-external",
        "arn:aws:s3:::sgpj-external/*",
        "arn:aws:s3:::sgpj-bronze",
        "arn:aws:s3:::sgpj-bronze/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "*"
    }
  ]
}
EOF

    aws --endpoint-url=$ENDPOINT_URL iam put-role-policy \
        --role-name sgpj-lambda-ingestion-role \
        --policy-name sgpj-lambda-ingestion-policy \
        --policy-document file:///tmp/lambda_policy.json

    # Criar CloudWatch Log Group
    echo "Criando CloudWatch Log Group..."
    aws --endpoint-url=$ENDPOINT_URL logs create-log-group \
        --log-group-name /aws/lambda/sgpj-data-ingestion \
        2>/dev/null || echo "Log group já existe"

    # Criar arquivo ZIP do Lambda
    echo "Empacotando código Lambda..."
    cd /Users/haniehashoori/Desktop/folders/sptech/sgpj/Infraestrutura/terraform/scripts
    zip -r lambda_ingestion.zip lambda_ingestion.py

    # Criar função Lambda
    echo "Criando função Lambda..."
    aws --endpoint-url=$ENDPOINT_URL lambda create-function \
        --function-name sgpj-data-ingestion \
        --runtime python3.11 \
        --role arn:aws:iam::000000000000:role/sgpj-lambda-ingestion-role \
        --handler lambda_ingestion.lambda_handler \
        --zip-file fileb://lambda_ingestion.zip \
        --environment Variables="{SOURCE_BUCKET=sgpj-external,TARGET_BUCKET=sgpj-bronze}" \
        --timeout 60 \
        --memory-size 256 \
        2>/dev/null || echo "Lambda já existe, atualizando..."

    # Atualizar se já existir
    aws --endpoint-url=$ENDPOINT_URL lambda update-function-code \
        --function-name sgpj-data-ingestion \
        --zip-file fileb://lambda_ingestion.zip \
        2>/dev/null || true

    # Aguardar Lambda ficar ativo
    echo "Aguardando Lambda ficar ativo..."
    for i in {1..30}; do
        STATE=$(aws --endpoint-url=$ENDPOINT_URL lambda get-function --function-name sgpj-data-ingestion --query 'Configuration.State' --output text 2>/dev/null || echo "Pending")
        if [ "$STATE" = "Active" ]; then
            echo "Lambda está ativo!"
            break
        fi
        echo "Estado: $STATE - aguardando... ($i/30)"
        sleep 2
    done

    # Configurar S3 Event Notification
    echo "Configurando S3 Event Notification..."
    cat > /tmp/s3_notification.json <<'EOF'
{
  "LambdaFunctionConfigurations": [
    {
      "LambdaFunctionArn": "arn:aws:lambda:us-east-1:000000000000:function:sgpj-data-ingestion",
      "Events": ["s3:ObjectCreated:*"],
      "Filter": {
        "Key": {
          "FilterRules": [
            {
              "Name": "suffix",
              "Value": ".json"
            }
          ]
        }
      }
    }
  ]
}
EOF

    aws --endpoint-url=$ENDPOINT_URL s3api put-bucket-notification-configuration \
        --bucket sgpj-external \
        --notification-configuration file:///tmp/s3_notification.json

    # Adicionar permissão para S3 invocar Lambda
    echo "Adicionando permissão S3 → Lambda..."
    aws --endpoint-url=$ENDPOINT_URL lambda add-permission \
        --function-name sgpj-data-ingestion \
        --principal s3.amazonaws.com \
        --statement-id AllowExecutionFromS3Bucket \
        --action "lambda:InvokeFunction" \
        --source-arn arn:aws:s3:::sgpj-external \
        2>/dev/null || echo "Permissão já existe"

    echo "=== Recursos Lambda criados com sucesso ==="
}

# ============================================================
# TESTAR INGESTÃO DE DADOS
# ============================================================

test_data_ingestion() {
    echo ""
    echo "=== Testando ingestão de dados ==="

    # Criar arquivo JSON de teste
    echo "Criando arquivo JSON de teste..."
    cat > /tmp/test_events.json <<'EOF'
[
  {"event_id": "1", "user_id": "100", "event_type": "click", "timestamp": "2024-10-10T10:30:00Z", "page": "/home"},
  {"event_id": "2", "user_id": "101", "event_type": "view", "timestamp": "2024-10-10T10:31:00Z", "page": "/product/123"},
  {"event_id": "3", "user_id": "100", "event_type": "purchase", "timestamp": "2024-10-10T10:35:00Z", "page": "/checkout", "amount": 99.90}
]
EOF

    # Enviar para bucket externo
    echo "Enviando arquivo para bucket sgpj-external..."
    aws --endpoint-url=$ENDPOINT_URL s3 cp /tmp/test_events.json s3://sgpj-external/test_events.json

    echo "Aguardando processamento do Lambda (10 segundos)..."
    sleep 10

    # Verificar logs do Lambda
    echo ""
    echo "=== Logs do Lambda ==="
    aws --endpoint-url=$ENDPOINT_URL logs tail /aws/lambda/sgpj-data-ingestion --since 10m --format short || echo "Nenhum log disponível"

    # Verificar dados no bucket bronze
    echo ""
    echo "=== Arquivos no bucket bronze ==="
    aws --endpoint-url=$ENDPOINT_URL s3 ls s3://sgpj-bronze/ --recursive

    # Tentar ler o arquivo processado
    echo ""
    echo "=== Conteúdo do arquivo processado ==="
    aws --endpoint-url=$ENDPOINT_URL s3 ls s3://sgpj-bronze/raw_data/ --recursive

    if [ $? -eq 0 ]; then
        # Pegar o primeiro arquivo
        FIRST_FILE=$(aws --endpoint-url=$ENDPOINT_URL s3 ls s3://sgpj-bronze/raw_data/ --recursive | head -1 | awk '{print $4}')
        if [ ! -z "$FIRST_FILE" ]; then
            echo "Lendo arquivo: $FIRST_FILE"
            aws --endpoint-url=$ENDPOINT_URL s3 cp s3://sgpj-bronze/$FIRST_FILE - | head -20
        fi
    fi

    echo ""
    echo "=== Teste concluído ==="
}

# ============================================================
# LIMPAR RECURSOS
# ============================================================

cleanup() {
    echo ""
    echo "=== Limpando recursos de teste ==="

    # Deletar arquivos de teste
    aws --endpoint-url=$ENDPOINT_URL s3 rm s3://sgpj-external/ --recursive 2>/dev/null || true
    aws --endpoint-url=$ENDPOINT_URL s3 rm s3://sgpj-bronze/raw_data/ --recursive 2>/dev/null || true

    # Remover notificação S3
    aws --endpoint-url=$ENDPOINT_URL s3api put-bucket-notification-configuration \
        --bucket sgpj-external \
        --notification-configuration '{}' 2>/dev/null || true

    # Deletar Lambda
    aws --endpoint-url=$ENDPOINT_URL lambda delete-function \
        --function-name sgpj-data-ingestion 2>/dev/null || echo "Lambda não existe"

    # Deletar IAM Role
    aws --endpoint-url=$ENDPOINT_URL iam delete-role-policy \
        --role-name sgpj-lambda-ingestion-role \
        --policy-name sgpj-lambda-ingestion-policy 2>/dev/null || true
    aws --endpoint-url=$ENDPOINT_URL iam delete-role \
        --role-name sgpj-lambda-ingestion-role 2>/dev/null || echo "Role não existe"

    # Deletar Log Group
    aws --endpoint-url=$ENDPOINT_URL logs delete-log-group \
        --log-group-name /aws/lambda/sgpj-data-ingestion 2>/dev/null || echo "Log group não existe"

    # Deletar bucket externo
    aws --endpoint-url=$ENDPOINT_URL s3 rb s3://sgpj-external --force 2>/dev/null || echo "Bucket não existe"

    echo "=== Limpeza concluída ==="
}

# ============================================================
# MAIN
# ============================================================

case "${1:-create}" in
    create)
        create_lambda_resources
        ;;
    test)
        test_data_ingestion
        ;;
    cleanup)
        cleanup
        ;;
    full)
        echo "Verificando se recursos já existem..."
        LAMBDA_EXISTS=$(aws --endpoint-url=$ENDPOINT_URL lambda get-function --function-name sgpj-data-ingestion --query 'Configuration.FunctionName' --output text 2>/dev/null || echo "")
        if [ -n "$LAMBDA_EXISTS" ]; then
            echo "Lambda já existe, pulando criação..."
        else
            create_lambda_resources
        fi
        test_data_ingestion
        ;;
    *)
        echo "Uso: $0 {create|test|cleanup|full}"
        echo "  create  - Cria recursos Lambda"
        echo "  test    - Testa ingestão de dados"
        echo "  cleanup - Remove recursos de teste"
        echo "  full    - Cria + Testa"
        exit 1
        ;;
esac
