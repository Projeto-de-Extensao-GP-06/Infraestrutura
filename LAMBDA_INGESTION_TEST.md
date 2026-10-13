# Lambda Ingestão de Dados Externos - Guia de Teste LocalStack

## Visão Geral

Este guia explica como testar a função Lambda de ingestão de dados externos para a camada Bronze do Data Lake usando LocalStack.

**Arquitetura:**
1. Bucket `sgpj-external` - Recebe arquivos JSON de fontes externas
2. Lambda `sgpj-data-ingestion` - Processa arquivos e salva no bucket bronze
3. Bucket `sgpj-bronze` - Armazena dados brutos com particionamento por data

**Fluxo:**
```
Arquivo JSON → sgpj-external → Evento S3 → Lambda → sgpj-bronze/raw_data/year=YYYY/month=MM/day=DD/hour=HH/
```

---

## Pré-requisitos

- Docker 20.10+
- Docker Compose 2.0+
- AWS CLI v2 (opcional, incluído no container)
- 8GB+ RAM disponível para o container LocalStack

---

## Estrutura de Arquivos

```
Infraestrutura/
├── terraform/
│   ├── scripts/
│   │   └── lambda_ingestion.py          # Código do Lambda
│   └── lambda_ingestion.tf             # Configuração Terraform (AWS real)
└── scripts/
    └── test/
        └── test_lambda_ingestion.sh    # Script de teste LocalStack
```

---

## Passo a Passo

### 1. Subir o LocalStack

```bash
cd /Users/haniehashoori/Desktop/folders/sptech/sgpj/Infraestrutura
docker-compose -f docker-compose.localstack.yml up -d
```

**O que acontece:**
- Inicia o container LocalStack com todos os serviços necessários (S3, Lambda, IAM, CloudWatch)
- Inicia o container aws-cli para testes
- Mapeia o script de inicialização `/etc/localstack/init/ready.d/localstack_init.sh`

### 2. Aguardar o LocalStack ficar pronto

```bash
# Verificar status
docker-compose -f docker-compose.localstack.yml ps

# Ver logs (Ctrl+C para sair)
docker-compose -f docker-compose.localstack.yml logs -f localstack
```

**Tempo estimado:** 60-120 segundos
**Sinal de pronto:** Logs mostram `"Ready."` e healthcheck passa

### 3. Inicializar a infraestrutura base (opcional)

Se ainda não criou os buckets do Data Lake:
```bash
# Via docker exec (recomendado)
docker exec sgpj-aws-cli /etc/localstack/init/ready.d/localstack_init.sh
```

Isso cria:
- VPC, Subnets, Security Groups
- Buckets S3: `sgpj-bronze`, `sgpj-silver`, `sgpj-gold`
- Glue Databases e Crawlers
- IAM Roles
- Outros recursos da infraestrutura

### 4. Criar recursos Lambda

```bash
./scripts/test/test_lambda_ingestion.sh create
```

**O que o script faz:**
1. Cria o bucket S3 `sgpj-external` com versionamento habilitado
2. Cria IAM Role `sgpj-lambda-ingestion-role` com permissões S3 e CloudWatch
3. Cria CloudWatch Log Group `/aws/lambda/sgpj-data-ingestion`
4. Empacota o código Python em ZIP
5. Cria a função Lambda `sgpj-data-ingestion` com:
   - Runtime: Python 3.11
   - Handler: `lambda_ingestion.lambda_handler`
   - Timeout: 60s
   - Memory: 256MB
   - Environment variables: `SOURCE_BUCKET=sgpj-external`, `TARGET_BUCKET=sgpj-bronze`
6. Configura S3 Event Notification no bucket `sgpj-external`:
   - Evento: `s3:ObjectCreated:*`
   - Filtro: apenas arquivos `.json`
7. Adiciona permissão para S3 invocar o Lambda

**Saída esperada:**
```
=== Criando recursos Lambda ===
Criando bucket sgpj-external...
Criando IAM Role para Lambda...
Criando CloudWatch Log Group...
Empacotando código Lambda...
Criando função Lambda...
Configurando S3 Event Notification...
Adicionando permissão S3 → Lambda...
=== Recursos Lambda criados com sucesso ===
```

### 5. Testar ingestão de dados

```bash
./scripts/test/test_lambda_ingestion.sh test
```

**O que o script faz:**
1. Cria um arquivo JSON de teste (`/tmp/test_events.json`) com dados de exemplo
2. Faz upload do arquivo para `s3://sgpj-external/test_events.json`
3. Aguarda 10 segundos para o Lambda processar
4. Mostra os logs do Lambda no CloudWatch
5. Lista os arquivos no bucket `sgpj-bronze`
6. Exibe o conteúdo do arquivo processado

**Arquivo de teste criado:**
```json
{"event_id": "1", "user_id": "100", "event_type": "click", "timestamp": "2024-10-10T10:30:00Z", "page": "/home"}
{"event_id": "2", "user_id": "101", "event_type": "view", "timestamp": "2024-10-10T10:31:00Z", "page": "/product/123"}
{"event_id": "3", "user_id": "100", "event_type": "purchase", "timestamp": "2024-10-10T10:35:00Z", "page": "/checkout", "amount": 99.90}
```

**Saída esperada:**
```
=== Testando ingestão de dados ===
Criando arquivo JSON de teste...
Enviando arquivo para bucket sgpj-external...
Aguardando processamento do Lambda (10 segundos)...

=== Logs do Lambda ===
Processando: s3://sgpj-external/test_events.json
Arquivo salvo em: s3://sgpj-bronze/raw_data/year=2024/month=10/day=10/hour=23/test_events.json

=== Arquivos no bucket bronze ===
2024-10-10 23:35:00     123 raw_data/year=2024/month=10/day=10/hour=23/test_events.json

=== Conteúdo do arquivo processado ===
{"event_id": "1", "user_id": "100", "event_type": "click", "timestamp": "2024-10-10T10:30:00Z", "page": "/home"}
{"event_id": "2", "user_id": "101", "event_type": "view", "timestamp": "2024-10-10T10:31:00Z", "page": "/product/123"}
{"event_id": "3", "user_id": "100", "event_type": "purchase", "timestamp": "2024-10-10T10:35:00Z", "page": "/checkout", "amount": 99.90}
```

### 6. Executar teste completo (criar + testar)

Para fazer tudo em um único comando:
```bash
./scripts/test/test_lambda_ingestion.sh full
```

Isso executa:
1. `create` - Cria todos os recursos Lambda
2. `test` - Testa a ingestão de dados

### 7. Limpar recursos de teste

Para remover apenas os recursos do teste Lambda (mantendo o resto da infraestrutura):
```bash
./scripts/test/test_lambda_ingestion.sh cleanup
```

**O que é removido:**
- Arquivos de teste dos buckets
- S3 Event Notification
- Função Lambda
- IAM Role e Policy
- CloudWatch Log Group
- Bucket `sgpj-external`

---

## Testes Manuais

### Via AWS CLI Local

```bash
# Configurar endpoint (se não estiver configurado)
export AWS_ACCESS_KEY_ID=test
export AWS_SECRET_ACCESS_KEY=test
export AWS_DEFAULT_REGION=us-east-1

# Verificar buckets
aws --endpoint-url=http://localhost:4566 s3 ls

# Verificar função Lambda
aws --endpoint-url=http://localhost:4566 lambda get-function --function-name sgpj-data-ingestion

# Verificar logs
aws --endpoint-url=http://localhost:4566 logs tail /aws/lambda/sgpj-data-ingestion --follow

# Enviar arquivo manualmente
cat > /tmp/meu_teste.json <<'EOF'
{"test": "manual", "timestamp": "2024-10-10T12:00:00Z"}
EOF
aws --endpoint-url=http://localhost:4566 s3 cp /tmp/meu_teste.json s3://sgpj-external/meu_teste.json

# Verificar resultado
aws --endpoint-url=http://localhost:4566 s3 ls s3://sgpj-bronze/raw_data/ --recursive
```

### Via Container aws-cli

```bash
# Entrar no container
docker exec -it sgpj-aws-cli bash

# Dentro do container, comandos são os mesmos (sem --endpoint-url)
aws s3 ls
aws lambda get-function --function-name sgpj-data-ingestion
```

---

## Particionamento dos Dados

O Lambda salva os arquivos no bucket bronze com o seguinte padrão de particionamento:

```
s3://sgpj-bronze/raw_data/year=YYYY/month=MM/day=DD/hour=HH/filename.json
```

**Exemplo:**
```
s3://sgpj-bronze/raw_data/year=2024/month=10/day=10/hour=23/test_events.json
```

**Metadados adicionais no objeto S3:**
- `source-bucket`: Bucket de origem
- `source-key`: Chave original do arquivo
- `ingestion-timestamp`: Timestamp do evento S3
- `original-filename`: Nome do arquivo original

---

## Troubleshooting

### Lambda não é acionado pelo evento S3

**Sintoma:** Arquivo enviado para `sgpj-external` mas nada acontece no bucket bronze.

**Verificações:**
```bash
# Verificar se a notificação está configurada
aws --endpoint-url=http://localhost:4566 s3api get-bucket-notification-configuration --bucket sgpj-external

# Verificar permissão do Lambda
aws --endpoint-url=http://localhost:4566 lambda get-policy --function-name sgpj-data-ingestion

# Verificar logs do LocalStack
docker-compose -f docker-compose.localstack.yml logs localstack | grep -i lambda
```

**Solução:** Reexecutar `./scripts/test/test_lambda_ingestion.sh create`

### Erro de permissão "Access Denied"

**Sintoma:** Lambda retorna erro de permissão ao acessar S3.

**Verificações:**
```bash
# Verificar IAM Role
aws --endpoint-url=http://localhost:4566 iam get-role --role-name sgpj-lambda-ingestion-role

# Verificar policy
aws --endpoint-url=http://localhost:4566 iam get-role-policy --role-name sgpj-lambda-ingestion-role --policy-name sgpj-lambda-ingestion-policy
```

**Solução:** O script de `create` configura as permissões corretamente. Reexecute se necessário.

### JSON inválido não é tratado

**Sintoma:** Arquivo JSON inválido causa erro no Lambda.

**Comportamento esperado:** O Lambda move arquivos inválidos para `s3://sgpj-bronze/error/` e deleta do bucket externo.

**Verificação:**
```bash
aws --endpoint-url=http://localhost:4566 s3 ls s3://sgpj-bronze/error/
```

### LocalStack não inicia

**Sintoma:** Container não fica healthy.

**Soluções:**
```bash
# Verificar logs
docker-compose -f docker-compose.localstack.yml logs localstack

# Verificar se porta 4566 está livre
lsof -i :4566

# Reiniciar do zero
docker-compose -f docker-compose.localstack.yml down -v
docker-compose -f docker-compose.localstack.yml up -d
```

---

## Limitações do LocalStack

| Funcionalidade | Status | Observação |
|---------------|--------|------------|
| S3 Events | ✅ Funciona | Eventos de criação de objeto funcionam |
| Lambda Python | ✅ Funciona | Runtime Python 3.11 suportado |
| S3 → Lambda trigger | ✅ Funciona | Notificações S3 acionam Lambda |
| IAM Roles | ✅ Funciona | Permissões funcionam corretamente |
| CloudWatch Logs | ⚠️ Parcial | Logs são criados mas pode haver delay |
| Particionamento | ✅ Funciona | Lógica de particionamento funciona |

---

## Próximos Passos

Após testar com sucesso no LocalStack:

1. **Aplicar no AWS real via Terraform:**
   ```bash
   cd terraform
   terraform init
   terraform apply
   ```

2. **Configurar fontes de dados reais:**
   - API Gateway endpoint para ingestão HTTP
   - Webhooks de sistemas externos
   - Integrations com parceiros

3. **Melhorias no Lambda:**
   - Adicionar validações de schema
   - Implementar DLQ (Dead Letter Queue) para erros
   - Adicionar métricas e alertas
   - Otimizar para grandes volumes

4. **Automatizar o processamento Bronze → Silver:**
   - Configurar EventBridge para acionar crawler Bronze após ingestão
   - Agendar jobs Glue para processamento contínuo

---

## Referências

- [LocalStack Lambda Docs](https://docs.localstack.cloud/user-guide/aws/lambda/)
- [AWS Lambda Python SDK](https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/lambda.html)
- [S3 Event Notifications](https://docs.aws.amazon.com/AmazonS3/latest/userguide/NotificationHowTo.html)
- [DATA_LAKE_ARCHITECTURE.md](./DATA_LAKE_ARCHITECTURE.md)
- [LOCALSTACK_USAGE.md](./LOCALSTACK_USAGE.md)
