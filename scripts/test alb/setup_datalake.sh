#!/bin/bash
set -e

echo "=== Setup Simplificado Data Lake para Teste Lambda ==="

ENDPOINT_URL="http://localhost:4566"
REGION="us-east-1"
AWS_ACCESS_KEY_ID="test"
AWS_SECRET_ACCESS_KEY="test"

export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION=$REGION

# Criar buckets do Data Lake
echo "Criando buckets do Data Lake..."

aws --endpoint-url=$ENDPOINT_URL s3 mb s3://sgpj-bronze 2>/dev/null || echo "Bucket sgpj-bronze ja existe"
aws --endpoint-url=$ENDPOINT_URL s3 mb s3://sgpj-silver 2>/dev/null || echo "Bucket sgpj-silver ja existe"
aws --endpoint-url=$ENDPOINT_URL s3 mb s3://sgpj-gold 2>/dev/null || echo "Bucket sgpj-gold ja existe"

# Habilitar versionamento
aws --endpoint-url=$ENDPOINT_URL s3api put-bucket-versioning \
    --bucket sgpj-bronze \
    --versioning-configuration Status=Enabled

aws --endpoint-url=$ENDPOINT_URL s3api put-bucket-versioning \
    --bucket sgpj-silver \
    --versioning-configuration Status=Enabled

aws --endpoint-url=$ENDPOINT_URL s3api put-bucket-versioning \
    --bucket sgpj-gold \
    --versioning-configuration Status=Enabled

# Habilitar criptografia
aws --endpoint-url=$ENDPOINT_URL s3api put-bucket-encryption \
    --bucket sgpj-bronze \
    --server-side-encryption-configuration '{
        "Rules": [
            {
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                }
            }
        ]
    }' 2>/dev/null || true

aws --endpoint-url=$ENDPOINT_URL s3api put-bucket-encryption \
    --bucket sgpj-silver \
    --server-side-encryption-configuration '{
        "Rules": [
            {
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                }
            }
        ]
    }' 2>/dev/null || true

aws --endpoint-url=$ENDPOINT_URL s3api put-bucket-encryption \
    --bucket sgpj-gold \
    --server-side-encryption-configuration '{
        "Rules": [
            {
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                }
            }
        ]
    }' 2>/dev/null || true

echo ""
echo "=== Buckets do Data Lake criados ==="
aws --endpoint-url=$ENDPOINT_URL s3 ls
