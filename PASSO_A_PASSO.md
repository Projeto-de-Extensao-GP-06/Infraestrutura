# Passo a Passo — Infraestrutura SGPJ (Grupo 06)

Arquitetura atual:

- **Banco:** MySQL 8.0 em container Docker na `ec2-db` (sem RDS)
- **Backend:** Spring Boot em container Docker nas `ec2-backend-a/b`, conectado automaticamente ao MySQL
- **Frontend:** Nginx em container Docker nas `ec2-app-a/b`, com proxy reverso para o backend
- **Conteúdo e configuração do Nginx** montados do EFS
- **Observabilidade:** Opcional — Grafana + Loki + Prometheus + Alloy (habilitada por flag)
- **Inventário do Ansible** gerado automaticamente pelo Terraform (`terraform/ansible.tf`)
- **Orquestração:** Terraform sobe a infra → Ansible (`site.yml`) faz o deploy de tudo em sequência

---

## 0) Pré-requisitos

### 0.1 Credenciais AWS e Chave SSH

Coloque sua chave privada na pasta `~/.ssh/`:

```bash
# No WSL:
cp "/mnt/c/Users/compu/OneDrive - SPTech School/GitHub/Grupo06/infra/Key-All.pem" ~/.ssh/vokey.pem
chmod 600 ~/.ssh/vokey.pem
```

Configure as credenciais AWS no terminal (copie do Vocareum):

```bash
# Substitua pelos valores do seu Lab no Vocareum
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."
export AWS_SESSION_TOKEN="..."
```

> As credenciais do AWS Academy expiram a cada ~4 horas. Ao renovar no Vocareum, repita esse `export`.

### 0.2 Arquivo de variáveis do Terraform — `terraform/terraform.tfvars`

Este arquivo **não é versionado** (está no `.gitignore`). Crie ou ajuste na pasta `terraform/`:

```hcl
Key-All    = "Key-All"         # nome do Key Pair na AWS
region     = "us-east-1"

# ── Banco de Dados MySQL (container na ec2-db) ────────────────────────────────
rds_password = "SUA_SENHA_DO_BANCO"
rds_db_name  = "sgpj"
rds_username = "admin"

# ── Observabilidade (Opcional) ────────────────────────────────────────────────
enable_observability       = false               # mude para true quando quiser Grafana/Prometheus/Loki
observability_allowed_cidr = "SEU_IP_PUBLICO/32" # curl https://ifconfig.me/ip

# ── Controle do Ansible pelo Terraform ───────────────────────────────────────
auto_run_ansible = false  # true = Terraform dispara o Ansible automaticamente após o apply
```

> **Descobrir seu IP:** `curl https://ifconfig.me/ip`

### 0.3 Alertas por e-mail — SMTP Gmail (opcional)

Só necessário se quiser alertas por e-mail via Alertmanager/Grafana:

**`ansible/playbooks/roles/alertmanager/defaults/main.yml`**
```yaml
alertmanager_smtp_from:     "SEU_EMAIL@gmail.com"
alertmanager_smtp_user:     "SEU_EMAIL@gmail.com"
alertmanager_smtp_password: "SENHA_APP_GMAIL"
alertmanager_alert_email:   "EMAIL_DESTINO@gmail.com"
```

**`ansible/playbooks/roles/grafana/defaults/main.yml`**
```yaml
grafana_smtp_user:         "SEU_EMAIL@gmail.com"
grafana_smtp_password:     "SENHA_APP_GMAIL"
grafana_smtp_from_address: "SEU_EMAIL@gmail.com"
grafana_alert_email:       "EMAIL_DESTINO@gmail.com"
```

> Para gerar uma App Password do Gmail: [myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords)
> A conta precisa ter **verificação em duas etapas ativada**.

---

## 1) Provisionar a infraestrutura com Terraform

```bash
cd infra/terraform
terraform init
terraform plan
terraform apply
```

O `terraform apply` faz tudo isso automaticamente:

1. Cria VPC, subnets, Security Groups, Internet Gateway
2. Sobe as EC2: `ec2-app-a`, `ec2-app-b`, `ec2-backend-a`, `ec2-backend-b`, `ec2-db`
3. Sobe a EC2 `ec2-observability` **somente se** `enable_observability = true`
4. Cria o Application Load Balancer (ALB)
5. Cria o EFS para volumes compartilhados
6. Cria os repositórios ECR (`sgpj-frontend`, `sgpj-backend`)
7. **Gera automaticamente** `ansible/inventories/production.ini` com os IPs reais das instâncias
8. **Gera automaticamente** `ansible/inventories/group_vars/all.yml` com variáveis de conexão (IP do banco, URLs do ECR, etc.)
9. Se `auto_run_ansible = true`: dispara o `site.yml` sozinho

Conferir saídas:

```bash
terraform output
```

Saídas úteis:
- `alb_dns` — URL do Load Balancer para acessar a aplicação
- `db_private_ip` — IP privado do banco MySQL
- `ecr_frontend_repository_url` — URL do repositório de imagens do frontend no ECR
- `ecr_backend_repository_url` — URL do repositório de imagens do backend no ECR

---

## 2) Instalar coleções do Ansible (só precisa fazer uma vez por máquina)

```bash
cd infra/ansible
ansible-galaxy collection install -r requirements.yml
```

---

## 3) Verificar conectividade SSH com as instâncias

```bash
cd infra/ansible
ansible all -i inventories/production.ini -m ping
```

Resultado esperado: `pong` de todas as instâncias.

---

## 4) Fazer deploy completo com o Playbook Mestre

O `site.yml` orquestra **tudo na ordem certa** com um único comando:

```bash
cd infra/ansible
ansible-playbook -i inventories/production.ini playbooks/site.yml
```

Ordem de execução:

| Passo | Playbook | O que faz |
| :---: | :--- | :--- |
| 1 | `docker.yml` | Instala Docker + monta EFS em todos os nós |
| 2 | `db.yml` | Sobe container MySQL 8.0 + inicializa `schema.sql` |
| 3 | `backend.yml` | Sobe container Spring Boot com `SPRING_DATASOURCE_URL` apontando para o MySQL |
| 4 | `nginx.yml` | Sobe container Nginx com `default.conf` gerado dinamicamente (proxy reverso para os backends) |
| 5 | `app.yml` | Publica o frontend React no EFS |
| 6 | `observability.yml` | Sobe Grafana/Prometheus/Loki/Alloy **somente se** `enable_observability: true` |

### Rodar playbooks individualmente (útil para redeploy parcial)

```bash
# Só o banco
ansible-playbook -i inventories/production.ini playbooks/db.yml

# Só o backend
ansible-playbook -i inventories/production.ini playbooks/backend.yml

# Só o Nginx/Frontend
ansible-playbook -i inventories/production.ini playbooks/nginx.yml

# Só a observabilidade
ansible-playbook -i inventories/production.ini playbooks/observability.yml
```

---

## 5) Habilitar ou Desabilitar a Observabilidade

A observabilidade é controlada pela variável `enable_observability` no `terraform.tfvars`.

**Para subir sem observabilidade** (testes rápidos / apresentações de Front+Back+DB):
```hcl
enable_observability = false
```

**Para subir com observabilidade completa** (Grafana, Prometheus, Loki, Alertmanager):
```hcl
enable_observability = true
```

Após alterar, aplique o Terraform novamente e execute o Ansible:

```bash
cd infra/terraform
terraform apply

cd ../ansible
ansible-playbook -i inventories/production.ini playbooks/site.yml
```

> **Por que é importante:** Com `false`, a EC2 `ec2-observability`, sua subnet dedicada e seus Security Groups não são criados, economizando tempo e custo.

### Portas de acesso à observabilidade:

| Serviço | Porta |
| :--- | :--- |
| Grafana | `3001` |
| Prometheus | `9090` |
| Alertmanager | `9093` |
| Loki (ingest) | `3100` |
| CloudWatch Exporter | `9106` |

---

## 6) Publicar imagens Docker no AWS ECR

Para usar imagens da sua própria aplicação (em vez de build local), faça o push para o ECR:

```bash
# Autenticar no ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.us-east-1.amazonaws.com

# Build e push do backend
docker build -t sgpj-backend ./backend
docker tag sgpj-backend:latest <ECR_BACKEND_URL>:latest
docker push <ECR_BACKEND_URL>:latest

# Build e push do frontend
docker build -t sgpj-frontend ./frontend
docker tag sgpj-frontend:latest <ECR_FRONTEND_URL>:latest
docker push <ECR_FRONTEND_URL>:latest
```

> Use `terraform output ecr_backend_repository_url` para obter as URLs exatas.

---

## 7) Verificação pós-deploy

### Verificar containers rodando

```bash
# Banco de dados
ansible db -i inventories/production.ini -m command -a "docker ps"

# Backend
ansible backend -i inventories/production.ini -m command -a "docker ps"

# Frontend/Nginx
ansible app -i inventories/production.ini -m command -a "docker ps"
```

### Verificar conectividade Back → Banco

```bash
# Verificar logs do container backend para confirmar conexão com o MySQL
ansible backend -i inventories/production.ini -m command -a "docker logs sgpj-backend --tail 30"
```

### Teste funcional da aplicação

```bash
# Pegar o DNS do ALB
cd infra/terraform
terraform output alb_dns
```

Abra no navegador: `http://<ALB_DNS>`

### Teste de geração de carga no ALB

```bash
for i in $(seq 1 200); do curl -s -o /dev/null -w "%{http_code}\n" http://<ALB_DNS>/; done
```

### Verificar EFS montado

```bash
ansible app,backend -i inventories/production.ini -m command -a "mount | grep efs"
```

### Validar Grafana (quando observabilidade está ativa)

1. Acesse `http://<IP_OBSERVABILITY>:3001` (login: `admin/admin`)
2. Vá em **Connections > Data Sources** — deve aparecer `Prometheus` e `Loki`
3. No Explore, valide métricas: query `up`
4. No Explore com Loki, valide logs: query `{job="docker"}`

---

## 8) Comandos de referência rápida

```bash
# ── TERRAFORM ──────────────────────────────────────────────────────────────────
cd infra/terraform
terraform init
terraform apply                          # sobe infra e gera inventário Ansible
terraform output                         # mostra saídas (IPs, URLs, DNS)
terraform destroy                        # destrói tudo

# ── ANSIBLE ────────────────────────────────────────────────────────────────────
cd infra/ansible
ansible all -i inventories/production.ini -m ping        # testa SSH em todos os hosts
ansible-playbook -i inventories/production.ini playbooks/site.yml  # deploy completo

# ── DOCKER (ad-hoc nas EC2) ───────────────────────────────────────────────────
ansible all   -i inventories/production.ini -m command -a "docker ps"
ansible db    -i inventories/production.ini -m command -a "docker logs sgpj-mysql --tail 20"
ansible backend -i inventories/production.ini -m command -a "docker logs sgpj-backend --tail 20"
ansible app   -i inventories/production.ini -m command -a "docker restart nginx"
```

---

## 9) CI/CD via GitHub Actions (automático)

O pipeline `.github/workflows/deploy.yml` está configurado para:

1. **Push na `main`** → dispara automaticamente.
2. **Execução manual** (aba Actions > Run workflow) → permite escolher se quer habilitar a observabilidade.

### Secrets necessárias no GitHub:

Adicione em **Settings > Secrets and variables > Actions**:

| Secret | Valor |
| :--- | :--- |
| `AWS_ACCESS_KEY_ID` | Chave de acesso da AWS |
| `AWS_SECRET_ACCESS_KEY` | Chave secreta |
| `AWS_SESSION_TOKEN` | Token de sessão (AWS Academy) |
| `AWS_REGION` | `us-east-1` |
| `SSH_PRIVATE_KEY` | Conteúdo completo do arquivo `vokey.pem` |
