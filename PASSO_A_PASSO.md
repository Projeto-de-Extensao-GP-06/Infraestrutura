# Passo a Passo — Infraestrutura SGPJ (Grupo 06)

> **Arquitetura Atualizada (Docker Swarm + AWS ECR):**
> - **Orquestração:** Docker Swarm em cluster (`ec2-app-a` Manager; `ec2-app-b`, `ec2-backend-a/b` Workers).
> - **Repositório de Imagens:** AWS ECR (`sgpj-frontend` e `sgpj-backend`).
> - **Deploy de Aplicação:** Stack Swarm com Rolling Update (zero downtime), alias de rede overlay `api.backend` e healthchecks.
> - **Banco:** MySQL 8.0 em container Docker na `ec2-db` (fora do Swarm por segurança/estado).
> - **Proxy / Ingress:** ALB na porta 80 balanceando para o serviço `nginx` (React SPA + Proxy reverso `/api/` para `api.backend:8080`).
> - **Observabilidade:** Opcional — Grafana + Loki + Prometheus + Alloy (habilitada por flag).

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

Verifique ou configure em `infra/terraform/terraform.tfvars`:

```hcl
Key-All    = "vockey"          # nome do Key Pair na AWS
region     = "us-east-1"

# ── Banco de Dados MySQL (container na ec2-db) ────────────────────────────────
rds_password = "SUA_SENHA_DO_BANCO"
rds_db_name  = "sgpj"
rds_username = "admin"

# ── Observabilidade (Opcional) ────────────────────────────────────────────────
enable_observability       = false               # mude para true quando quiser Grafana/Prometheus/Loki
observability_allowed_cidr = "SEU_IP_PUBLICO/32" # curl https://ifconfig.me/ip

# ── Execução Automática do Ansible pelo Terraform ─────────────────────────────
auto_run_ansible = true   # true = Terraform dispara o Ansible automaticamente após o apply
```

---

## 1) Primeira Vez (Do Zero — Infraestrutura ainda não existe)

Como a stack do Docker Swarm precisa puxar as imagens do ECR no momento da inicialização das instâncias, a ordem de provisionamento inicial segue 3 passos simples:

### Passo 1.1 — Criar os Repositórios ECR (Apenas 1x na vida)
```bash
cd infra/terraform

terraform apply \
  -target=aws_ecr_repository.frontend \
  -target=aws_ecr_repository.backend \
  -target=aws_ecr_lifecycle_policy.frontend \
  -target=aws_ecr_lifecycle_policy.backend \
  --auto-approve
```
> Isso cria os repositórios ECR vazios no AWS (~30s). **Nunca mais precisará rodar com `-target`.**

### Passo 1.2 — Fazer o Build e Push Inicial das Imagens para o ECR
```bash
cd ../scripts
./deploy.sh all
```
> O script automatiza tudo: compila React (`dist/`), empacota Spring Boot (`.jar`), cria imagens Docker e faz o push para o ECR. Como detecta que o Swarm ainda não está no ar, ele envia as imagens e aguarda a criação da infra.

### Passo 1.3 — Subir Toda a Infraestrutura (EC2s + Swarm + Stack)
```bash
cd ../terraform
terraform apply --auto-approve
```
O Terraform criará:
1. VPC, subnets, Security Groups (com portas do Swarm `2377`, `7946`, `4789`) e Internet Gateway
2. EC2s (`ec2-app-a`, `ec2-app-b`, `ec2-backend-a`, `ec2-backend-b`, `ec2-db`)
3. Application Load Balancer (ALB) e EFS compartilhado
4. Gera dinamicamente `ansible/inventories/production.ini` e `group_vars/all.yml`
5. **Dispara o Ansible automaticamente:**
   - Instala Docker e monta o EFS
   - Sobe o MySQL 8.0 na `ec2-db` e roda `schema.sql`
   - Inicializa o **Docker Swarm**: `ec2-app-a` vira Manager, as outras EC2 viram Workers
   - Autentica no ECR e faz o `docker stack deploy` da aplicação SGPJ

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

### O que o `./deploy.sh all` faz sozinho:
1. Executa `npm ci` e `npm run build` na pasta do Frontend gerando `dist/`
2. Executa `mvn package -DskipTests` na pasta do Backend gerando o `.jar`
3. Constrói as imagens Docker locais usando os `Dockerfile` validados
4. Autentica no Amazon ECR
5. Envia as novas imagens para os repositórios ECR
6. Conecta via SSH no Swarm Manager (`ec2-app-a`) e dispara:
   `docker service update --image <ECR_URL>:latest --with-registry-auth`
7. O Docker Swarm detecta a alteração de hash da imagem e realiza um **Rolling Update** (1 réplica por vez, sem downtime).

---

## 3) Referência de Comandos do `deploy.sh`

Os caminhos dos projetos já vêm pré-configurados no script:
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

## 5) `terraform destroy` e Proteção do ECR

Caso precise destruir a infraestrutura para economizar horas no AWS Academy:

```bash
cd infra/terraform
terraform destroy --auto-approve
```

### O que acontece:
- **Destruído:** EC2s, VPC, Subnets, Security Groups, ALB, EFS.
- **Protegido:** Os repositórios ECR (`sgpj-frontend` e `sgpj-backend`) e suas imagens **NÃO são apagados**, pois possuem a diretiva `lifecycle { prevent_destroy = true }`.

> Quando for subir a infra novamente após um destroy, **você não precisa fazer o Passo 1.1 nem 1.2**. Basta rodar direto `terraform apply --auto-approve`, pois as imagens já estão salvas no ECR!

---

## 6) Habilitar ou Desabilitar a Observabilidade

A observabilidade é controlada pela flag `enable_observability` no `terraform.tfvars`.

- `enable_observability = false`: Não cria a EC2 de observabilidade, poupando custos.
- `enable_observability = true`: Provisiona Grafana (`3001`), Prometheus (`9090`), Alertmanager (`9093`) e Loki (`3100`).

---

## 7) Verificação e Troubleshooting no Swarm

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
