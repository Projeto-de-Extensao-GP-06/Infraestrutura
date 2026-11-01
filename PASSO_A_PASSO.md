# Passo a Passo — Infraestrutura SGPJ (Grupo 06)

> **Arquitetura Atualizada (Docker Compose + AWS ECR + Agente IA MarIA + Observabilidade & Fluent Bit):**
> - **Orquestração:** Docker Compose nativo por nó (`ec2-app-a/b` para Nginx/Frontend; `ec2-backend-a/b` para Spring Boot + RabbitMQ + Agente IA MarIA).
> - **Agente IA (MarIA):** FastAPI Python 3.12 (`sgpj-agent`) rodando na porta `8000` nos nós de backend. Roteado pelo Nginx através de `/agent/` (que remove o prefixo e repassa para a API interna). Integração com Google Gemini (LLM) configurável via `/opt/app-backend/agent.env`.
> - **Mensageria:** RabbitMQ 4 (`rabbitmq:4-management`) restrito aos nós de backend. AMQP na porta `5672`, painel web na porta `15672` (acessível via VPC / IP público das EC2 app).
> - **Repositório de Imagens:** AWS ECR (`sgpj-frontend`, `sgpj-backend` e `sgpj-agent`).
> - **Deploy de Aplicação:** Atualização contínua com scripts automatizados (`deploy.ps1` e `deploy.sh`), ECR e Ansible.
> - **Banco:** MySQL 8.0 em container Docker na `ec2-db` (isolado por segurança e persistência de dados).
> - **Proxy / Ingress:** ALB na porta 80 balanceando para o serviço `nginx` (React SPA + Proxy reverso `/api/` para Spring Boot na porta 8080 e `/agent/` para o FastAPI na porta 8000).
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
> As credenciais do AWS Academy expiram a cada ~4 horas. Sempre que renovar a sessão, repita o `export` acima ou no PowerShell `$env:AWS_ACCESS_KEY_ID="..."`.

### 0.2 Arquivo de variáveis do Terraform — `terraform/terraform.tfvars`

Configurado em `infra/terraform/terraform.tfvars`:

```hcl
Key-All = "vockey"
region  = "us-east-1"

# ── Observabilidade (Grafana, Prometheus, Loki) ─────────────────
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

Como os nós precisam puxar as imagens do ECR no momento da inicialização das instâncias, a ordem de provisionamento inicial segue 3 passos simples:

### Passo 1.1 — Criar os Repositórios ECR (Apenas 1x na vida)

No **PowerShell** (Windows), as aspas duplas em cada `-target` são obrigatórias:

```powershell
cd infra/terraform

terraform apply `
  -target="aws_ecr_repository.frontend" `
  -target="aws_ecr_repository.backend" `
  -target="aws_ecr_repository.agent" `
  -target="aws_ecr_lifecycle_policy.frontend" `
  -target="aws_ecr_lifecycle_policy.backend" `
  -target="aws_ecr_lifecycle_policy.agent" `
  -auto-approve
```

*(Se preferir rodar no terminal **WSL / Linux**)*:
```bash
cd infra/terraform

terraform apply \
  -target="aws_ecr_repository.frontend" \
  -target="aws_ecr_repository.backend" \
  -target="aws_ecr_repository.agent" \
  -target="aws_ecr_lifecycle_policy.frontend" \
  -target="aws_ecr_lifecycle_policy.backend" \
  -target="aws_ecr_lifecycle_policy.agent" \
  --auto-approve
```
> Isso cria os 3 repositórios ECR vazios na AWS (`sgpj-frontend`, `sgpj-backend` e `sgpj-agent`). **Nunca mais precisará rodar com `-target`.**

### Passo 1.2 — Fazer o Build e Push Inicial das Imagens para o ECR

No **PowerShell** (Windows nativo — recomendado, pois usa seu Docker Desktop e AWS CLI do Windows):
```powershell
cd ../scripts
.\deploy.ps1 all
```

*(Ou via **WSL / Git Bash**)*:
```bash
cd ../scripts
./deploy.sh all
```
> O script automatiza tudo: compila React (`dist/`), empacota Spring Boot (`.jar`), constrói a imagem do Agente IA MarIA (`Agent-Backend`), cria as tags e faz o push para o ECR.

### Passo 1.3 — Subir Toda a Infraestrutura (EC2s + Nginx + Backend + Agente + Observabilidade + Fluent Bit)
```bash
cd ../terraform
terraform apply --auto-approve
```
O Terraform criará:
1. VPC, subnets, Security Groups (incluindo portas `8080` para Spring Boot e `8000` para o Agente MarIA) e Internet Gateway
2. EC2s: `ec2-app-a`, `ec2-app-b` (`t3.small`), `ec2-backend-a`, `ec2-backend-b` (`t3.medium` — para Spring Boot, RabbitMQ e Agente FastAPI), `ec2-db`, `ec2-observability` (`t3.small`)
3. Application Load Balancer (ALB) e EFS compartilhado
4. Repositórios ECR e Buckets S3 (Bronze, Silver, Gold e Athena Results)
5. Glue Catalog Database `sgpj_logs_bronze` e Athena Workgroup `sgpj-logs-analytics`
6. Gera dinamicamente `ansible/inventories/production.ini` e `group_vars/all.yml`
7. **Dispara o Ansible automaticamente:**
   - Instala Docker e monta o EFS
   - Sobe o MySQL 8.0 na `ec2-db` e roda `schema.sql`
   - Configura o Nginx com proxy reverso para `/api/` (porta 8080) e `/agent/` (porta 8000)
   - Autentica no ECR e sobe o `docker-compose` do Backend (`backend`, `rabbitmq` e `agent`)
   - Provisiona o stack de Observabilidade (Grafana, Loki, Prometheus, Alertmanager)
   - Instala e inicia o **Fluent Bit** em todas as máquinas para enviar logs ao S3 Bronze

---

## 2) Configuração do Agente IA MarIA (Chave LLM Gemini)

O Agente MarIA é executado como um container Docker FastAPI junto à stack do backend, na porta 8000.

### 2.1 Como funciona o arquivo de ambiente (`agent.env`)
Assim como o `application.properties` no Backend, as configurações do Agente ficam centralizadas em:
`/opt/app-backend/agent.env` na máquina EC2.

Conteúdo padrão gerado:
```env
LLM_API_KEY=""
LLM_MODEL="gemini-2.0-flash"
ANONYMIZATION_KEY="1111222233334444"
```

### 2.2 Como adicionar ou alterar a chave da LLM (Google Gemini)

Você pode configurar a chave de duas maneiras:

#### Opção A — Direto na EC2 (Sem precisar rodar build ou scripts):
1. Acesse a EC2 do backend via SSH:
   ```bash
   ssh -i ~/.ssh/vockey.pem ubuntu@<IP_BACKEND>
   ```
2. Edite o arquivo:
   ```bash
   nano /opt/app-backend/agent.env
   ```
3. Cole sua API Key obtida no [Google AI Studio](https://aistudio.google.com/app/apikey) em `LLM_API_KEY`:
   ```env
   LLM_API_KEY="AIzaSy..."
   ```
4. Salve (`Ctrl + O`, `Enter` e `Ctrl + X`) e reinicie o container do agente:
   ```bash
   cd /opt/app-backend
   docker compose restart agent
   ```

#### Opção B — Pelo Ansible (Automatizado):
1. No seu computador, edite [`infra/ansible/secrets.yml`](file:///c:/Users/compu/OneDrive%20-%20SPTech%20School/GitHub/Grupo06/infra/ansible/secrets.yml):
   ```yaml
   llm_api_key: "AIzaSy..."
   ```
2. No WSL, execute:
   ```bash
   ./run_ansible.sh
   ```

---

## 3) Atualizações de Código no Dia a Dia (Deploy Contínuo)

Com a infraestrutura já rodando na AWS, **você não precisa mexer no Terraform**. Sempre que alterar código no Frontend, Backend ou Agente:

```powershell
# No PowerShell (Windows nativo):
cd infra\scripts
.\deploy.ps1 all      # Atualiza Frontend, Backend e Agente
```
*(Ou no terminal WSL/Linux: `./deploy.sh all`)*

Após o envio das imagens ao ECR, execute o Ansible para que as EC2s baixem as versões mais recentes:
```bash
./run_ansible.sh
```

---

## 4) Referência de Comandos dos Scripts de Deploy

### No PowerShell (`deploy.ps1`):
```powershell
.\deploy.ps1           # Build + push de Frontend, Backend e Agente (padrão)
.\deploy.ps1 all       # Mesmo comportamento do padrão
.\deploy.ps1 frontend  # Build e push exclusivo do Frontend
.\deploy.ps1 backend   # Build e push exclusivo do Backend
.\deploy.ps1 agent     # Build e push exclusivo do Agente MarIA
```

### No WSL / Bash (`deploy.sh`):
```bash
./deploy.sh           # Build + push de Frontend, Backend e Agente (padrão)
./deploy.sh all       # Mesmo comportamento do padrão
./deploy.sh frontend  # Build e push exclusivo do Frontend
./deploy.sh backend   # Build e push exclusivo do Backend
./deploy.sh agent     # Build e push exclusivo do Agente MarIA
./deploy.sh db        # Re-provisiona o MySQL e executa schema.sql via Ansible
```

---

## 5) Gerenciamento do Banco de Dados (MySQL)

O banco de dados roda isolado em Docker puro na `ec2-db`.

| O que você quer alterar | Onde editar | Como aplicar |
| :--- | :--- | :--- |
| Tabelas, schema ou inserts iniciais | [`infra/ansible/playbooks/roles/db/files/schema.sql`](file:///c:/Users/compu/OneDrive%20-%20SPTech%20School/GitHub/Grupo06/infra/ansible/playbooks/roles/db/files/schema.sql) | `./deploy.sh db` |
| Versão da imagem MySQL ou portas | [`infra/ansible/playbooks/roles/db/defaults/main.yml`](file:///c:/Users/compu/OneDrive%20-%20SPTech%20School/GitHub/Grupo06/infra/ansible/playbooks/roles/db/defaults/main.yml) | `./deploy.sh db` |
| Configurações do mysqld / charset | [`infra/ansible/playbooks/roles/db/tasks/main.yml`](file:///c:/Users/compu/OneDrive%20-%20SPTech%20School/GitHub/Grupo06/infra/ansible/playbooks/roles/db/tasks/main.yml) | `./deploy.sh db` |

---

## 6) `terraform destroy` sem Perder as Imagens do ECR

Por padrão, os repositórios ECR (`sgpj-frontend`, `sgpj-backend` e `sgpj-agent`) possuem a diretiva de segurança `lifecycle { prevent_destroy = true }` no arquivo `ecr.tf`. 

> [!WARNING]
> Se você tentar rodar `terraform destroy` diretamente, o Terraform bloqueará a execução com erro de `prevent_destroy`. Isso impede a perda acidental das imagens Docker.

Para destruir a infraestrutura cara (EC2s, ALB, NAT Gateway, EFS) e **manter o ECR e suas imagens 100% salvos na AWS**:

### Passo 6.1 — Remover o ECR do controle do Terraform (sem apagar na AWS)

No **PowerShell** (Windows):
```powershell
cd infra/terraform

terraform state rm aws_ecr_lifecycle_policy.frontend aws_ecr_lifecycle_policy.backend aws_ecr_lifecycle_policy.agent aws_ecr_repository.frontend aws_ecr_repository.backend aws_ecr_repository.agent
```

*(Ou no terminal **WSL / Linux**)*:
```bash
cd infra/terraform

terraform state rm aws_ecr_lifecycle_policy.frontend aws_ecr_lifecycle_policy.backend aws_ecr_lifecycle_policy.agent aws_ecr_repository.frontend aws_ecr_repository.backend aws_ecr_repository.agent
```

### Passo 6.2 — Destruir a Infraestrutura Restante
```powershell
terraform destroy -auto-approve
```

---

### Como Subir a Infraestrutura Novamente no Futuro (Reconectar ECR existente)

Quando você for subir tudo de novo na próxima sessão do AWS Academy:

1. **Reconecte o Terraform aos repositórios ECR existentes**:
   ```powershell
   cd infra/terraform

   terraform import aws_ecr_repository.frontend sgpj-frontend
   terraform import aws_ecr_repository.backend sgpj-backend
   terraform import aws_ecr_repository.agent sgpj-agent
   terraform import aws_ecr_lifecycle_policy.frontend sgpj-frontend
   terraform import aws_ecr_lifecycle_policy.backend sgpj-backend
   terraform import aws_ecr_lifecycle_policy.agent sgpj-agent
   ```
2. **Suba toda a infraestrutura:**
   ```powershell
   terraform apply -auto-approve
   ```
   > Como as imagens Docker já estavam salvas no ECR, as EC2s subirão instantaneamente puxando as imagens prontas sem você precisar compilar tudo do zero de novo!

---

## 7) Como Acessar e Usar a Observabilidade (Grafana)

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

## 8) Pipeline de Logs com Fluent Bit e AWS Athena

### 8.1 Como funciona
- O **Fluent Bit** roda como serviço nativo em cada EC2.
- Ele coleta logs locais de:
  - Containers Docker: `/var/lib/docker/containers/*/*-json.log`
  - Nginx: `/var/log/nginx/`
  - Sistema Operacional: `/var/log/syslog` e `/var/log/auth.log`
- Comprime em Gzip e descarrega automaticamente no S3 Bronze:
  `s3://sgpj-bronze-<account-id>/logs/` particionado em Hive (`year=YYYY/month=MM/day=DD/hour=HH/`).

### 8.2 Como consultar no AWS Athena (Web Console)
1. Acesse o **AWS Athena** no console AWS da sua conta.
2. No menu superior direito do Athena, mude o **Workgroup** para:
   `sgpj-logs-analytics`
3. Selecione o banco de dados:
   `sgpj_logs_bronze`
4. Na aba **Saved Queries**, você já encontrará consultas analíticas prontas criadas pelo Terraform:
   - `logs_containers_erros_e_excecoes`: Lista erros e stack traces do Backend e Agente.
   - `logs_nginx_status_distribuicao`: Estatísticas de status HTTP (200, 4xx, 5xx).
   - `logs_nginx_top_rotas_acessadas`: Endpoints mais acessados da API e Agente (`/agent/`).
   - `logs_os_auditoria_falhas_ssh`: Tentativas de login inválidas no SSH.
5. Se as tabelas ainda não tiverem sido criadas pelo Glue Crawler, crie-as executando o script SQL contido em:
   [`infra/scripts/athena/create_tables.sql`](file:///c:/Users/compu/OneDrive%20-%20SPTech%20School/GitHub/Grupo06/infra/scripts/athena/create_tables.sql).

---

## 9) Verificação e Troubleshooting nas EC2s

Para verificar o status dos containers em produção:

```bash
# Conectar no Backend (ec2-backend-a ou ec2-backend-b) via SSH:
ssh -i ~/.ssh/vockey.pem ubuntu@<IP_PRIVADO_BACKEND>

# Listar os containers em execução:
docker ps

# Ver logs do Agente MarIA em tempo real:
docker logs -f --tail 50 sgpj-agent

# Testar o healthcheck localmente na EC2:
curl -s http://localhost:8000/health
# Deve retornar: {"status":"ok"}

# Ver logs do Spring Boot Backend:
docker logs -f --tail 50 sgpj-backend

# Ver logs do RabbitMQ:
docker logs -f --tail 50 rabbitmq
```

---

## 10) Integração com Microsoft OneDrive (OAuth2)

- Em ambiente local (`localhost:8080`), a integração e reconexão com o OneDrive funcionam de ponta a ponta sem necessidade de SSL/HTTPS (exceção nativa da Microsoft para loopback).
- Para produção e nuvem AWS (onde a Microsoft exige HTTPS e o ALB possui DNS efêmero que muda a cada `destroy/apply`), consulte o guia completo de arquitetura, SSL/Certificados e proxy Cloudflare em:
  [`INTEGRACAO_ONEDRIVE.md`](file:///c:/Users/compu/OneDrive%20-%20SPTech%20School/GitHub/Grupo06/infra/INTEGRACAO_ONEDRIVE.md) (também disponível em [`Backend/docs/INTEGRACAO_ONEDRIVE.md`](file:///c:/Users/compu/OneDrive%20-%20SPTech%20School/GitHub/Grupo06/Backend/docs/INTEGRACAO_ONEDRIVE.md)).
