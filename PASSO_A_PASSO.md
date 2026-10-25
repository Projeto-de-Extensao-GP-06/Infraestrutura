# Passo a Passo — Infraestrutura SGPJ (Grupo 06)

> **Arquitetura Atualizada (Docker Swarm + AWS ECR + Observabilidade & Fluent Bit):**
> - **Orquestração:** Docker Swarm em cluster (`ec2-app-a` Manager; `ec2-app-b`, `ec2-backend-a/b` Workers).
> - **Repositório de Imagens:** AWS ECR (`sgpj-frontend` e `sgpj-backend`).
> - **Deploy de Aplicação:** Stack Swarm com Rolling Update (zero downtime), alias de rede overlay `api.backend` e healthchecks.
> - **Banco:** MySQL 8.0 em container Docker na `ec2-db` (fora do Swarm por segurança/estado).
> - **Proxy / Ingress:** ALB na porta 80 balanceando para o serviço `nginx` (React SPA + Proxy reverso `/api/` para `api.backend:8080`).
> - **Observabilidade Ativa:** Grafana (`3001`) + Loki (`3100`) + Prometheus (`9090`) liberados para acesso público na EC2 de observabilidade.
> - **Log Shipping & Data Lake:** Fluent Bit instalado em todas as EC2, enviando logs compactados em Gzip para o S3 Bronze Tier (`s3://sgpj-bronze-<account-id>/logs/`), catalogados via AWS Glue e consultáveis via AWS Athena.

---

## 0) Pré-requisitos e Configuração Inicial

### 0.1 Credenciais AWS e Chave SSH

Coloque sua chave privada na pasta `~/.ssh/` no WSL:

```bash
mkdir -p ~/.ssh
cp "/mnt/c/Users/compu/OneDrive - SPTech School/GitHub/Grupo06/infra/vockey.pem" ~/.ssh/vockey.pem
chmod 400 ~/.ssh/vockey.pem
```

Configure as credenciais AWS no terminal (copie do Vocareum/AWS Academy):

```bash
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."
```

> [!WARNING]
> As credenciais do AWS Academy expiram a cada ~4 horas. Sempre que renovar a sessão, repita o `export` acima.

### 0.2 Arquivo de variáveis do Terraform — `terraform/terraform.tfvars`

Configurado em `infra/terraform/terraform.tfvars`:

```hcl
Key-All = "vockey"
region  = "us-east-1"

# ── Observabilidade (Grafana, Prometheus, Loki) ─────────────────
# Habilitado com acesso publico (0.0.0.0/0) para demonstracao e avaliacao
enable_observability       = true
observability_allowed_cidr = "0.0.0.0/0"
observability_existing_instance_profile_name = "LabInstanceProfile"

# ── Execucao Automatica do Ansible pelo Terraform ────────────
auto_run_ansible = true

# ── Data Lake IAM (Glue Crawlers/Jobs - bloqueado no AWS Academy) ─
enable_data_lake_iam = false

# ── Banco de Dados MySQL na EC2 db ───────────────────────────
rds_password = "sgpj96321"
rds_db_name  = "sgpj"
rds_username = "admin"
```

---

## 1) Primeira Vez (Do Zero — Infraestrutura ainda não existe)

Como a stack do Docker Swarm precisa puxar as imagens do ECR no momento da inicialização das instâncias, a ordem de provisionamento inicial segue 3 passos simples:

### Passo 1.1 — Criar os Repositórios ECR (Apenas 1x na vida)

No **PowerShell** (Windows), as aspas duplas em cada `-target` são obrigatórias para evitar que o ponto seja interpretado:

```powershell
cd infra/terraform

terraform apply -target="aws_ecr_repository.frontend" -target="aws_ecr_repository.backend" -target="aws_ecr_lifecycle_policy.frontend" -target="aws_ecr_lifecycle_policy.backend" -auto-approve
```

*(Se preferir rodar no terminal **WSL / Linux**)*:
```bash
cd infra/terraform

terraform apply \
  -target="aws_ecr_repository.frontend" \
  -target="aws_ecr_repository.backend" \
  -target="aws_ecr_lifecycle_policy.frontend" \
  -target="aws_ecr_lifecycle_policy.backend" \
  -auto-approve
```
> Isso cria os repositórios ECR vazios na AWS (~30s). **Nunca mais precisará rodar com `-target`.**

### Passo 1.2 — Fazer o Build e Push Inicial das Imagens para o ECR

No **PowerShell** (Windows nativo — recomendado, pois usa seu Docker Desktop e AWS CLI do Windows):
```powershell
cd ../scripts
.\deploy.ps1 all
```

*(Ou via **WSL / Git Bash**)*:
```bash
cd ../scripts
bash deploy.sh all
```
> O script automatiza tudo: compila React (`dist/`), empacota Spring Boot (`.jar`), cria imagens Docker e faz o push para o ECR. Ele detecta automaticamente o ID da sua conta AWS e a região, e como o Swarm ainda não está no ar, ele apenas envia as imagens com sucesso e avisa para você prosseguir para o Passo 1.3!

### Passo 1.3 — Subir Toda a Infraestrutura (EC2s + Swarm + Stack + Observabilidade + Fluent Bit)
```bash
cd ../terraform
terraform apply --auto-approve
```
O Terraform criará:
1. VPC, subnets, Security Groups (com portas do Swarm `2377`, `7946`, `4789` e Observabilidade pública `3001`, `9090`) e Internet Gateway
2. EC2s: `ec2-app-a`, `ec2-app-b`, `ec2-backend-a`, `ec2-backend-b`, `ec2-db` e `ec2-observability`
3. Application Load Balancer (ALB) e EFS compartilhado
4. Repositórios ECR e Buckets S3 (Bronze, Silver, Gold e Athena Results)
5. Glue Catalog Database `sgpj_logs_bronze` e Athena Workgroup `sgpj-logs-analytics`
6. Gera dinamicamente `ansible/inventories/production.ini` e `group_vars/all.yml`
7. **Dispara o Ansible automaticamente:**
   - Instala Docker e monta o EFS
   - Sobe o MySQL 8.0 na `ec2-db` e roda `schema.sql`
   - Inicializa o **Docker Swarm**: `ec2-app-a` vira Manager, as outras EC2 viram Workers
   - Autentica no ECR e faz o `docker stack deploy` da aplicação SGPJ
   - Provisiona o stack de Observabilidade (Grafana, Loki, Prometheus, Alertmanager)
   - Instala e inicia o **Fluent Bit** em todas as máquinas para enviar logs ao S3 Bronze

---

## 2) Atualizações de Código no Dia a Dia (Deploy Contínuo)

Com a infraestrutura já rodando na AWS, **você não precisa mexer no Terraform**. Sempre que alterar código no Frontend ou Backend:

```bash
# 1. Certifique-se de que as credenciais AWS estão exportadas no terminal
export AWS_ACCESS_KEY_ID=...
export AWS_SECRET_ACCESS_KEY=...
export AWS_SESSION_TOKEN=...

# 2. Execute o deploy simplificado
cd infra/scripts
./deploy.sh all
```

---

## 3) Referência de Comandos do `deploy.sh`

```bash
./deploy.sh           # Build + push + update de Frontend e Backend (padrão)
./deploy.sh all       # Mesmo comportamento de ./deploy.sh
./deploy.sh frontend  # Build e deploy exclusivo do Frontend
./deploy.sh backend   # Build e deploy exclusivo do Backend
./deploy.sh db        # Re-executa o provisionamento do MySQL e schema.sql via Ansible
```

---

## 4) Gerenciamento do Banco de Dados (MySQL)

O banco de dados roda isolado em Docker puro na `ec2-db` (fora do Swarm, garantindo consistência de volume e estado).

| O que você quer alterar | Onde editar | Como aplicar |
| :--- | :--- | :--- |
| Tabelas, schema ou inserts iniciais | [`infra/scripts/test/schema.sql`](file:///c:/Users/compu/OneDrive%20-%20SPTech%20School/GitHub/Grupo06/infra/scripts/test/schema.sql) | `./deploy.sh db` |
| Versão da imagem MySQL ou portas | [`infra/ansible/playbooks/roles/db/defaults/main.yml`](file:///c:/Users/compu/OneDrive%20-%20SPTech%20School/GitHub/Grupo06/infra/ansible/playbooks/roles/db/defaults/main.yml) | `./deploy.sh db` |
| Configurações do mysqld / charset | [`infra/ansible/playbooks/roles/db/tasks/main.yml`](file:///c:/Users/compu/OneDrive%20-%20SPTech%20School/GitHub/Grupo06/infra/ansible/playbooks/roles/db/tasks/main.yml) | `./deploy.sh db` |

---

## 5) `terraform destroy` sem Perder as Imagens do ECR

Por padrão, os repositórios ECR (`sgpj-frontend` e `sgpj-backend`) possuem a diretiva de segurança `lifecycle { prevent_destroy = true }` no arquivo `ecr.tf`. 

> [!WARNING]
> Se você tentar rodar `terraform destroy` diretamente, o Terraform **bloqueará a execução** com o erro:
> `Error: Instance cannot be destroyed ... has lifecycle.prevent_destroy set to true.`
> Isso é uma **trava de segurança intencional** para impedir a perda acidental das imagens Docker que você compilou e enviou.

Para destruir toda a infraestrutura cara (EC2s, ALB, NAT Gateway, EFS) e **manter o ECR e suas imagens 100% intactos e salvos na AWS**, siga o procedimento abaixo:

### Passo 5.1 — Remover o ECR do controle do Terraform (sem apagar na AWS)

No **PowerShell** (Windows):
```powershell
cd infra/terraform

terraform state rm aws_ecr_lifecycle_policy.frontend aws_ecr_lifecycle_policy.backend aws_ecr_repository.frontend aws_ecr_repository.backend
```

*(Ou no terminal **WSL / Linux**)*:
```bash
cd infra/terraform

terraform state rm \
  aws_ecr_lifecycle_policy.frontend \
  aws_ecr_lifecycle_policy.backend \
  aws_ecr_repository.frontend \
  aws_ecr_repository.backend
```
> **O que isso faz:** O Terraform apenas remove esses recursos do seu arquivo de estado local (`terraform.tfstate`). Os repositórios ECR e todas as imagens Docker permanecem **vivos e preservados na sua conta AWS** (custando apenas centavos de storage).

### Passo 5.2 — Destruir a Infraestrutura Restante

Agora o Terraform destruirá todo o restante (EC2s, ALB, VPC, EFS, Banco) zerando os custos de computação:

```powershell
terraform destroy -auto-approve
```

---

### Como Subir a Infraestrutura Novamente no Futuro (Reconectar ECR existente)

Quando você for subir tudo de novo no próximo laboratório/sessão do AWS Academy:

1. **Reconecte o Terraform aos repositórios ECR existentes** (leva 5 segundos):
   ```powershell
   cd infra/terraform

   terraform import aws_ecr_repository.frontend sgpj-frontend
   terraform import aws_ecr_repository.backend sgpj-backend
   terraform import aws_ecr_lifecycle_policy.frontend sgpj-frontend
   terraform import aws_ecr_lifecycle_policy.backend sgpj-backend
   ```
2. **Suba toda a infraestrutura:**
   ```powershell
   terraform apply -auto-approve
   ```
   > Como as imagens Docker já estavam salvas no ECR, o Swarm subirá instantaneamente puxando as imagens prontas sem você precisar compilar tudo do zero de novo!

---

## 6) Como Acessar e Usar a Observabilidade (Grafana)

A instância de observabilidade está configurada com acesso liberado (`0.0.0.0/0`):

1. Obtenha o IP público da instância de observabilidade:
   ```bash
   cd infra/terraform
   terraform output observability_public_ip
   ```
2. Abra no navegador:
   - **Grafana:** `http://<IP_OBSERVABILITY>:3001` (Usuário: `admin` / Senha: `admin`)
   - **Prometheus:** `http://<IP_OBSERVABILITY>:9090`
   - **Alertmanager:** `http://<IP_OBSERVABILITY>:9093`
3. No Grafana:
   - Em **Explore**, selecione **Loki** para buscar logs de containers em tempo real (ex: `{job="docker"}`).
   - Selecione **Prometheus** para visualizar métricas de CPU, memória e rede via Node Exporter.

---

## 7) Pipeline de Logs com Fluent Bit e AWS Athena

### 7.1 Como funciona
- O **Fluent Bit** roda como serviço nativo em cada EC2.
- Ele coleta logs locais de:
  - Containers Docker: `/var/lib/docker/containers/*/*-json.log`
  - Nginx: `/var/log/nginx/`
  - Sistema Operacional: `/var/log/syslog` e `/var/log/auth.log`
- Comprime em Gzip e descarrega automaticamente no S3 Bronze:
  `s3://sgpj-bronze-<account-id>/logs/` particionado em Hive (`year=YYYY/month=MM/day=DD/hour=HH/`).

### 7.2 Como consultar no AWS Athena (Web Console)
1. Acesse o **AWS Athena** no console AWS da sua conta.
2. No menu superior direito do Athena, mude o **Workgroup** para:
   `sgpj-logs-analytics`
3. Selecione o banco de dados:
   `sgpj_logs_bronze`
4. Na aba **Saved Queries**, você já encontrará consultas analíticas prontas criadas pelo Terraform:
   - `logs_containers_erros_e_excecoes`: Lista erros e stack traces do Backend.
   - `logs_nginx_status_distribuicao`: Estatísticas de status HTTP (200, 4xx, 5xx).
   - `logs_nginx_top_rotas_acessadas`: Endpoints mais acessados da API.
   - `logs_os_auditoria_falhas_ssh`: Tentativas de login inválidas no SSH.
5. Se as tabelas ainda não tiverem sido criadas pelo Glue Crawler, crie-as executando o script SQL contido em:
   [`infra/scripts/athena/create_tables.sql`](file:///c:/Users/compu/OneDrive%20-%20SPTech%20School/GitHub/Grupo06/infra/scripts/athena/create_tables.sql).

---

## 8) Verificação e Troubleshooting no Swarm

Para verificar o status das réplicas e containers em produção:

```bash
# Conectar no Manager (ec2-app-a) via SSH:
ssh -i ~/.ssh/vockey.pem ubuntu@<IP_PUBLICO_APP_A>

# Listar os nós do cluster Swarm:
docker node ls

# Listar os serviços da stack:
docker service ls

# Ver o estado do rolling update e réplicas:
docker service ps sgpj_nginx
docker service ps sgpj_backend

# Visualizar logs em tempo real:
docker service logs -f --tail 50 sgpj_nginx
docker service logs -f --tail 50 sgpj_backend

# Acessar a aplicação via DNS do Load Balancer:
# http://<ALB_DNS>
```

---

## 9) Integração com Microsoft OneDrive (OAuth2)

- Em ambiente local (`localhost:8080`), a integração e reconexão com o OneDrive funcionam de ponta a ponta sem necessidade de SSL/HTTPS (exceção nativa da Microsoft para loopback).
- Para produção e nuvem AWS (onde a Microsoft exige HTTPS e o ALB possui DNS efêmero que muda a cada `destroy/apply`), consulte o guia completo de arquitetura, SSL/Certificados e proxy Cloudflare em:
  [`INTEGRACAO_ONEDRIVE.md`](file:///c:/Users/compu/OneDrive%20-%20SPTech%20School/GitHub/Grupo06/infra/INTEGRACAO_ONEDRIVE.md) (também disponível em [`Backend/docs/INTEGRACAO_ONEDRIVE.md`](file:///c:/Users/compu/OneDrive%20-%20SPTech%20School/GitHub/Grupo06/Backend/docs/INTEGRACAO_ONEDRIVE.md)).

