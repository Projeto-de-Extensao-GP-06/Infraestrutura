# LocalStack Usage Guide - SGPJ Full Infrastructure

## Visão Geral

Este guia explica como usar o LocalStack para desenvolver e testar **toda a infraestrutura SGPJ** localmente, simulando serviços AWS completos:
- **Networking**: VPC, Subnets, IGW, NAT Gateway, Route Tables, NACLs
- **Compute**: EC2 Instances (App, Backend, DB, Observability)
- **Load Balancing**: ALB, Target Groups, Listeners
- **Database**: RDS MySQL
- **Storage**: EFS, S3 (Data Lake: Bronze/Silver/Gold)
- **Data Lake**: Glue Databases, Crawlers, ETL Jobs, IAM Roles
- **Observability**: CloudWatch Dashboards, IAM Roles para exporters
- **Security**: Security Groups, IAM Roles/Policies

---

## Pré-requisitos

- Docker 20.10+
- Docker Compose 2.0+
- AWS CLI v2 (opcional, para testes manuais)
- **8GB+ RAM** disponível para o container (recomendado para todos os serviços)
- 10GB+ espaço em disco

---

## Início Rápido

### 1. Subir o ambiente

```bash
cd /Users/haniehashoori/Desktop/folders/sptech/sgpj/Infraestrutura
docker-compose -f docker-compose.localstack.yml up -d
```

### 2. Aguardar healthcheck (60-120s - mais serviços = mais tempo)

```bash
# Verificar status
docker-compose -f docker-compose.localstack.yml ps

# Ver logs
docker-compose -f docker-compose.localstack.yml logs -f localstack
```

### 3. Executar inicialização completa da infraestrutura

```bash
# Opção A: Via docker exec (recomendado - roda dentro do container aws-cli)
docker exec sgpj-aws-cli /etc/localstack/init/ready.d/localstack_init.sh

# Opção B: Script direto (se aws-cli configurado localmente)
./scripts/localstack_init.sh
```

> **Nota**: A inicialização completa cria ~50+ recursos e pode levar 2-5 minutos.

---

## Estrutura do Docker Compose Atualizada

```yaml
services:
  localstack:
    image: localstack/localstack:3.5
    container_name: sgpj-localstack
    ports:
      - "4566:4566"           # LocalStack Gateway
      - "4510-4559:4510-4559" # External services port range
    environment:
      - SERVICES=s3,glue,iam,sts,logs,ec2,vpc,rds,efs,elbv2,cloudwatch,kinesis,events,sqs,sns,lambda,dynamodb,secretsmanager,ssm,apigateway,stepfunctions
      - DEBUG=1
      - DATA_DIR=/var/lib/localstack/data
      - AWS_DEFAULT_REGION=us-east-1
      - AWS_ACCESS_KEY_ID=test
      - AWS_SECRET_ACCESS_KEY=test
      - HOSTNAME_EXTERNAL=localstack
      - EDGE_PORT=4566
      - EXECUTION_ENV=docker
      - LAMBDA_EXECUTOR=docker
      - DOCKER_HOST=unix:///var/run/docker.sock
    volumes:
      - "${LOCALSTACK_VOLUME_DIR:-./localstack_data}:/var/lib/localstack/data"
      - "/var/run/docker.sock:/var/run/docker.sock"
      - "./scripts/localstack_init.sh:/etc/localstack/init/ready.d/localstack_init.sh"
    networks:
      - sgpj-network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4566/_localstack/health"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 60s
    deploy:
      resources:
        limits:
          cpus: '4'
          memory: 8G

  aws-cli:
    image: amazon/aws-cli:2.15
    container_name: sgpj-aws-cli
    depends_on:
      localstack:
        condition: service_healthy
    environment:
      - AWS_ACCESS_KEY_ID=test
      - AWS_SECRET_ACCESS_KEY=test
      - AWS_DEFAULT_REGION=us-east-1
    entrypoint: ""
    command: sleep infinity
    networks:
      - sgpj-network

networks:
  sgpj-network:
    driver: bridge
    name: sgpj-localstack-network
```

---

## Endpoints e Credenciais

| Configuração | Valor |
|--------------|-------|
| **Endpoint URL** | `http://localhost:4566` |
| **Region** | `us-east-1` |
| **Access Key** | `test` |
| **Secret Key** | `test` |

### Configurar AWS CLI local (opcional)

```bash
aws configure set aws_access_key_id test
aws configure set aws_secret_access_key test
aws configure set default.region us-east-1
aws configure set default.output json

# Testar conexão
aws --endpoint-url=http://localhost:4566 s3 ls
```

---

## Recursos Criados Automaticamente

O script `localstack_init.sh` cria **todos** os recursos da sua infraestrutura Terraform:

### Networking
- **VPC**: `sgpj-vpc` (10.0.0.0/16)
- **Internet Gateway**: `sgpj-igw`
- **NAT Gateway**: `sgpj-ngw-main` (em subnet pública AZ-a)
- **Subnets** (7 total):
  - `sgpj-subnet-public-a` (10.0.1.0/24, us-east-1a)
  - `sgpj-subnet-public-b` (10.0.2.0/24, us-east-1b)
  - `sgpj-subnet-public-obs` (10.0.3.0/24, us-east-1c)
  - `sgpj-subnet-private-backend-a` (10.0.11.0/24, us-east-1a)
  - `sgpj-subnet-private-backend-b` (10.0.12.0/24, us-east-1b)
  - `sgpj-subnet-private-db-a` (10.0.21.0/24, us-east-1a)
  - `sgpj-subnet-private-db-b` (10.0.22.0/24, us-east-1b)
- **Route Tables**: Pública (→ IGW) e Privada (→ NAT)
- **NACLs**: Pública e Privada com regras equivalentes ao Terraform

### Security Groups (7)
| SG Name | Descrição | Regras Principais |
|---------|-----------|-------------------|
| `alb` | Load Balancer | HTTP 80 (0.0.0.0/0) |
| `app-public` | App público | SSH 22, HTTP 80, Node Exporter 9100, OTLP 4317/4318 (VPC) |
| `backend-private` | Backend privado | SSH 22, Spring Boot 8080, Node Exporter 9100 (VPC) |
| `db-private` | DB EC2 | MySQL 3306 (from backend SG), SSH 22, Node Exporter 9100 (VPC) |
| `observability` | Observabilidade | SSH 22, Prometheus 9090, Grafana 3001, Alertmanager 9093, Loki 3100, OTLP 4317/4318, Tempo 3200, Node Exporter 9100 |
| `efs` | EFS NFS | NFS 2049 (VPC) |
| `rds-mysql` | RDS MySQL | MySQL 3306 (from backend SG e db SG) |

### EC2 Instances (6)
| Name | Tipo | Subnet | SG | IP Público |
|------|------|--------|-----|------------|
| `ec2-app-a` | t3.micro | public-a | app-public | Sim |
| `ec2-app-b` | t3.micro | public-b | app-public | Sim |
| `ec2-backend-a` | t3.micro | private-backend-a | backend-private | Não |
| `ec2-backend-b` | t3.micro | private-backend-b | backend-private | Não |
| `ec2-db` | t3.micro | private-db-a | db-private | Não |
| `ec2-observability` | t3.micro | public-obs | observability | Sim (20GB gp3) |

### Load Balancer
- **ALB**: `alb-app` (internet-facing, subnets public-a/public-b)
- **Target Group**: `tg-app` (HTTP:80, health check /)
- **Targets**: ec2-app-a:80, ec2-app-b:80
- **Listener**: HTTP:80 → forward to tg-app

### RDS
- **Instance**: `sgpj-mysql` (MySQL 8.0, db.t3.micro, 20GB gp3, encrypted)
- **Subnet Group**: `sgpj-rds-subnet-group` (private-db-a, private-db-b)
- **Credenciais**: admin / admin123
- **Database**: `sgpjdb`

### EFS
- **File System**: `sgpj-app-efs` (encrypted)
- **Mount Targets**: private-backend-a, private-backend-b (SG: efs)

### IAM Roles (3)
| Role | Trust Policy | Políticas |
|------|--------------|-----------|
| `sgpj-glue-crawler-role` | glue.amazonaws.com | S3 (bronze/silver/gold), Glue, Logs |
| `sgpj-glue-job-role` | glue.amazonaws.com | S3 (bronze/silver/gold), Glue, Logs |
| `sgpj-observability-ec2-role` | ec2.amazonaws.com | CloudWatch ReadOnly, EC2/ELB/RDS/EFS Describe |

### S3 Data Lake (3 buckets)
| Bucket | Versionamento | Criptografia | Uso |
|--------|---------------|--------------|-----|
| `sgpj-bronze` | ✅ | AES256 | Dados brutos |
| `sgpj-silver` | ✅ | AES256 | Dados limpos + scripts ETL |
| `sgpj-gold` | ✅ | AES256 | Dados agregados + scripts ETL |

### Glue
- **Databases**: `sgpj_bronze`, `sgpj_silver`, `sgpj_gold`
- **Crawlers**: `sgpj-bronze-crawler`, `sgpj-silver-crawler`, `sgpj-gold-crawler`
- **ETL Scripts** (em S3):
  - `s3://sgpj-silver/scripts/bronze_to_silver.py`
  - `s3://sgpj-gold/scripts/silver_to_gold.py`

---

## Comandos Úteis por Serviço

### VPC & Networking

```bash
# VPC
aws --endpoint-url=http://localhost:4566 ec2 describe-vpcs --vpc-ids $VPC_ID

# Subnets
aws --endpoint-url=http://localhost:4566 ec2 describe-subnets --filters Name=vpc-id,Values=$VPC_ID

# Internet Gateway
aws --endpoint-url=http://localhost:4566 ec2 describe-internet-gateways --filters Name=attachment.vpc-id,Values=$VPC_ID

# NAT Gateway
aws --endpoint-url=http://localhost:4566 ec2 describe-nat-gateways --filter Name=vpc-id,Values=$VPC_ID

# Route Tables
aws --endpoint-url=http://localhost:4566 ec2 describe-route-tables --filters Name=vpc-id,Values=$VPC_ID

# NACLs
aws --endpoint-url=http://localhost:4566 ec2 describe-network-acls --filters Name=vpc-id,Values=$VPC_ID
```

### Security Groups

```bash
# Listar todos
aws --endpoint-url=http://localhost:4566 ec2 describe-security-groups --filters Name=vpc-id,Values=$VPC_ID

# Ver regras de um SG específico
aws --endpoint-url=http://localhost:4566 ec2 describe-security-groups --group-ids $SG_ALB
```

### EC2

```bash
# Listar instâncias
aws --endpoint-url=http://localhost:4566 ec2 describe-instances --filters Name=vpc-id,Values=$VPC_ID

# Ver IPs públicos das instâncias de app
aws --endpoint-url=http://localhost:4566 ec2 describe-instances \
    --filters Name=tag:Name,Values=ec2-app-a,ec2-app-b \
    --query 'Reservations[].Instances[].{Name:Tags[?Key==`Name`].Value|[0],PublicIP:PublicIpAddress,PrivateIP:PrivateIpAddress,State:State.Name}'
```

### ALB

```bash
# Ver ALB
aws --endpoint-url=http://localhost:4566 elbv2 describe-load-balancers --names alb-app

# Ver Target Group e health
aws --endpoint-url=http://localhost:4566 elbv2 describe-target-groups --names tg-app
aws --endpoint-url=http://localhost:4566 elbv2 describe-target-health --target-group-arn $TG_ARN

# DNS do ALB para testar
aws --endpoint-url=http://localhost:4566 elbv2 describe-load-balancers --names alb-app --query 'LoadBalancers[0].DNSName'
```

### RDS

```bash
# Ver instância
aws --endpoint-url=http://localhost:4566 rds describe-db-instances --db-instance-identifier sgpj-mysql

# Endpoint de conexão
aws --endpoint-url=http://localhost:4566 rds describe-db-instances --db-instance-identifier sgpj-mysql --query 'DBInstances[0].Endpoint.Address'
```

### EFS

```bash
# Ver file system
aws --endpoint-url=http://localhost:4566 efs describe-file-systems --file-system-id $EFS_ID

# Ver mount targets
aws --endpoint-url=http://localhost:4566 efs describe-mount-targets --file-system-id $EFS_ID
```

### IAM

```bash
# Listar roles SGPJ
aws --endpoint-url=http://localhost:4566 iam list-roles --query 'Roles[?contains(RoleName, `sgpj`)].{RoleName:RoleName,Arn:Arn}'

# Ver role e políticas
aws --endpoint-url=http://localhost:4566 iam get-role --role-name sgpj-glue-crawler-role
aws --endpoint-url=http://localhost:4566 iam list-role-policies --role-name sgpj-glue-crawler-role
aws --endpoint-url=http://localhost:4566 iam get-role-policy --role-name sgpj-glue-crawler-role --policy-name sgpj-glue-crawler-policy
```

### S3 Data Lake

```bash
# Listar buckets
aws --endpoint-url=http://localhost:4566 s3 ls

# Ver versionamento/encriptação
aws --endpoint-url=http://localhost:4566 s3api get-bucket-versioning --bucket sgpj-bronze
aws --endpoint-url=http://localhost:4566 s3api get-bucket-encryption --bucket sgpj-bronze

# Listar objetos recursivamente
aws --endpoint-url=http://localhost:4566 s3 ls s3://sgpj-bronze/ --recursive
aws --endpoint-url=http://localhost:4566 s3 ls s3://sgpj-silver/ --recursive
aws --endpoint-url=http://localhost:4566 s3 ls s3://sgpj-gold/ --recursive
```

### Glue

```bash
# Databases
aws --endpoint-url=http://localhost:4566 glue get-databases

# Crawlers
aws --endpoint-url=http://localhost:4566 glue get-crawlers
aws --endpoint-url=http://localhost:4566 glue get-crawler --name sgpj-bronze-crawler

# Executar crawlers
aws --endpoint-url=http://localhost:4566 glue start-crawler --name sgpj-bronze-crawler
aws --endpoint-url=http://localhost:4566 glue start-crawler --name sgpj-silver-crawler
aws --endpoint-url=http://localhost:4566 glue start-crawler --name sgpj-gold-crawler

# Tabelas (após crawler)
aws --endpoint-url=http://localhost:4566 glue get-tables --database-name sgpj_bronze
aws --endpoint-url=http://localhost:4566 glue get-tables --database-name sgpj_silver
aws --endpoint-url=http://localhost:4566 glue get-tables --database-name sgpj_gold

# Jobs ETL (catálogo apenas - LocalStack não executa Spark)
aws --endpoint-url=http://localhost:4566 glue get-jobs
aws --endpoint-url=http://localhost:4566 glue get-job --job-name sgpj-bronze-to-silver
```

### CloudWatch

```bash
# Dashboards
aws --endpoint-url=http://localhost:4566 cloudwatch list-dashboards
aws --endpoint-url=http://localhost:4566 cloudwatch get-dashboard --dashboard-name SGPJ-Infraestrutura

# Métricas (limitado no LocalStack)
aws --endpoint-url=http://localhost:4566 cloudwatch list-metrics --namespace AWS/EC2
```

---

## Testando o Fluxo Completo Data Lake

### 1. Enviar dados para Bronze

```bash
cat > /tmp/test_events.json <<'EOF'
{"event_id": "1", "user_id": "100", "event_type": "click", "timestamp": "2024-01-15T10:30:00Z", "page": "/home"}
{"event_id": "2", "user_id": "101", "event_type": "view", "timestamp": "2024-01-15T10:31:00Z", "page": "/product/123"}
{"event_id": "3", "user_id": "100", "event_type": "purchase", "timestamp": "2024-01-15T10:35:00Z", "page": "/checkout", "amount": 99.90}
EOF

aws --endpoint-url=http://localhost:4566 s3 cp /tmp/test_events.json s3://sgpj-bronze/events/
```

### 2. Executar crawler Bronze

```bash
aws --endpoint-url=http://localhost:4566 glue start-crawler --name sgpj-bronze-crawler

# Aguardar
while true; do
    STATE=$(aws --endpoint-url=http://localhost:4566 glue get-crawler --name sgpj-bronze-crawler --query 'Crawler.State' --output text)
    echo "Estado: $STATE"
    [ "$STATE" = "READY" ] && break
    sleep 5
done
```

### 3. Verificar tabelas Bronze

```bash
aws --endpoint-url=http://localhost:4566 glue get-tables --database-name sgpj_bronze --query 'TableList[].Name'
```

### 4. Simular processamento Bronze → Silver (manual - LocalStack não roda Spark)

```bash
# Baixar, processar localmente e subir para Silver
aws --endpoint-url=http://localhost:4566 s3 cp s3://sgpj-bronze/events/test_events.json - | \
    jq -c '.' | \
    aws --endpoint-url=http://localhost:4566 s3 cp - s3://sgpj-silver/events/processed.json
```

### 5. Executar crawler Silver

```bash
aws --endpoint-url=http://localhost:4566 glue start-crawler --name sgpj-silver-crawler
```

### 6. Verificar tabelas Silver

```bash
aws --endpoint-url=http://localhost:4566 glue get-tables --database-name sgpj_silver --query 'TableList[].Name'
```

### 7. Simular processamento Silver → Gold

```bash
aws --endpoint-url=http://localhost:4566 s3 cp s3://sgpj-silver/events/processed.json - | \
    jq -s 'group_by(.event_type) | map({event_type: .[0].event_type, total_events: length, unique_users: (map(.user_id) | unique | length)})' | \
    aws --endpoint-url=http://localhost:4566 s3 cp - s3://sgpj-gold/metrics/event_summary.json
```

### 8. Executar crawler Gold

```bash
aws --endpoint-url=http://localhost:4566 glue start-crawler --name sgpj-gold-crawler
```

### 9. Verificar tabelas Gold

```bash
aws --endpoint-url=http://localhost:4566 glue get-tables --database-name sgpj_gold --query 'TableList[].Name'
```

---

## Integração com Terraform

### Usar LocalStack como provider Terraform

Crie um arquivo `provider.localstack.tf` (não commitado):

```hcl
# provider.localstack.tf - Para desenvolvimento local
provider "aws" {
  region                      = "us-east-1"
  access_key                  = "test"
  secret_key                  = "test"
  s3_force_path_style         = true
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  endpoints {
    s3            = "http://localhost:4566"
    glue          = "http://localhost:4566"
    iam           = "http://localhost:4566"
    sts           = "http://localhost:4566"
    cloudwatch    = "http://localhost:4566"
    ec2           = "http://localhost:4566"
    vpc           = "http://localhost:4566"
    rds           = "http://localhost:4566"
    efs           = "http://localhost:4566"
    elbv2         = "http://localhost:4566"
    # Adicione outros conforme necessário
  }
}
```

```bash
# Inicializar e aplicar contra LocalStack
terraform init
terraform apply -var-file=terraform.tfvars
```

> **Dica**: Use `terraform apply -target=resource.name` para testar recursos específicos.

---

## Limitações Conhecidas do LocalStack

| Funcionalidade | Status | Observação |
|----------------|--------|------------|
| **VPC/Subnets/IGW/NAT** | ✅ Funciona | Completo |
| **Route Tables/NACLs** | ✅ Funciona | Completo |
| **Security Groups** | ✅ Funciona | Completo |
| **EC2 Instances** | ⚠️ Parcial | Inicia/para, mas não executa user-data real |
| **ALB/Target Groups** | ✅ Funciona | Health checks básicos |
| **RDS MySQL** | ⚠️ Parcial | Cria instância, mas engine não roda real |
| **EFS** | ⚠️ Parcial | Cria FS/mount targets, NFS não funcional |
| **S3 (básico)** | ✅ Funciona | Completo |
| **S3 Versioning/Encryption** | ✅ Funciona | Completo |
| **IAM Roles/Policies** | ✅ Funciona | Completo |
| **Glue Databases** | ✅ Funciona | Completo |
| **Glue Crawlers** | ⚠️ Parcial | Schema inference limitado |
| **Glue Jobs (Spark)** | ❌ Não funciona | LocalStack não executa Spark |
| **CloudWatch Dashboards** | ⚠️ Parcial | Cria, mas métricas não coletadas |
| **CloudWatch Metrics** | ❌ Não funciona | Não há coleta real |

**Importante**: 
- EC2 user-data **não executa** no LocalStack - instâncias ficam "running" mas sem software instalado
- RDS **não aceita conexões reais** - apenas API de gerenciamento
- Glue Jobs **não processam dados** - use processamento local (pyspark/duckdb/pandas) e suba resultados para S3
- Para testar conectividade real entre serviços, use AWS real ou moto para testes unitários

---

## Persistência de Dados

Os dados persistem em `./localstack_data/` (volume mapeado):

```bash
# Ver estrutura
ls -la localstack_data/

# Backup
tar -czf localstack_backup_$(date +%Y%m%d).tar.gz localstack_data/

# Restore
tar -xzf localstack_backup_20240115.tar.gz
```

---

## Parar e Limpar

```bash
# Parar containers (mantém dados)
docker-compose -f docker-compose.localstack.yml down

# Parar e remover volumes (limpa tudo)
docker-compose -f docker-compose.localstack.yml down -v

# Remover imagens
docker rmi localstack/localstack:3.5 amazon/aws-cli:2.15
```

---

## Troubleshooting

### LocalStack não inicia / saúde não fica "healthy"

```bash
# Ver logs detalhados
docker-compose -f docker-compose.localstack.yml logs localstack | head -200

# Verificar porta 4566 livre
lsof -i :4566

# Verificar recursos do container
docker stats sgpj-localstack

# Reiniciar do zero
docker-compose -f docker-compose.localstack.yml down -v
docker-compose -f docker-compose.localstack.yml up -d
```

### Script de init falha ou trava

```bash
# Ver logs do script
docker-compose -f docker-compose.localstack.yml logs -f aws-cli

# Executar passo a passo para debug
docker exec -it sgpj-aws-cli bash
# Dentro do container:
/etc/localstack/init/ready.d/localstack_init.sh
```

### Recursos não criados / erros de API

```bash
# Verificar quais serviços estão running
curl -s http://localhost:4566/_localstack/health | jq '.'

# Aumentar timeout de healthcheck no docker-compose se necessário
# start_period: 120s
```

### Permissões (Access Denied)

```bash
# Verificar se role existe e tem políticas
aws --endpoint-url=http://localhost:4566 iam get-role --role-name sgpj-glue-crawler-role
aws --endpoint-url=http://localhost:4566 iam list-role-policies --role-name sgpj-glue-crawler-role

# Recriar tudo (execute o script de init novamente)
docker exec sgpj-aws-cli /etc/localstack/init/ready.d/localstack_init.sh
```

---

## Recursos Adicionais

- [LocalStack Docs](https://docs.localstack.cloud/)
- [LocalStack Service Coverage](https://docs.localstack.cloud/references/coverage/)
- [AWS CLI Reference](https://awscli.amazonaws.com/v2/documentation/api/latest/reference/index.html)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)