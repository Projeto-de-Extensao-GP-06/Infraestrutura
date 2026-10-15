# Manual da Nova Arquitetura e Pipeline CI/CD

Este documento orienta sobre a nova arquitetura refatorada, explicando como utilizar os novos recursos: eliminação do RDS, provisionamento do MySQL em container, repositórios AWS ECR, observabilidade opcional e esteira de CI/CD via GitHub Actions com Ansible automatizado.

---

## 1. O que Mudou na Arquitetura

1. **Eliminação do RDS:**
   - O AWS RDS MySQL foi completamente removido do Terraform.
   - O banco de dados agora roda como um container Docker oficial `mysql:8.0` na instância `ec2-db`, com volume montado para persistência de dados em `/opt/mysql/data` e carga automática do `schema.sql`.
   - Tempo de provisionamento reduzido de **~15 minutos** para **menos de 30 segundos**.

2. **AWS ECR (Elastic Container Registry):**
   - Repositórios nativos criados via Terraform (`terraform/ecr.tf`):
     - `sgpj-frontend`
     - `sgpj-backend`
   - Política de retenção configurada para manter as últimas 10 imagens, economizando espaço.

3. **Observabilidade Opcional (Toggle):**
   - No arquivo `terraform/terraform.tfvars`:
     ```hcl
     enable_observability = false # Mude para true quando quiser subir Grafana, Prometheus, Loki, Tempo
     ```
   - Quando `false`:
     - A EC2 `ec2-observability`, sua subnet e seus security groups **não são criados**.
     - O inventário do Ansible omite o grupo `[observability]` e os playbooks de observabilidade são ignorados com segurança.
     - Permite testes ultrarrápidos e econômicos de Front + Back + DB.

4. **Conexão Automática das Camadas (Zero Configuração Manual):**
   - **Banco de Dados (MySQL):** Sobe na porta 3306 da `ec2-db`.
   - **Backend (Spring Boot):** Recebe automaticamente a URL `jdbc:mysql://<IP_EC2_DB>:3306/sgpj`.
   - **Frontend (Nginx):** O arquivo de configuração `default.conf` do Nginx é gerado dinamicamente via template Jinja2, criando um bloco `upstream backend_servers` com os IPs privados dos backends (`ec2-backend-a` e `ec2-backend-b`) e fazendo proxy reverso nas requisições `/api/`.

5. **Orquestração Automática do Ansible pelo Terraform:**
   - O Terraform (`terraform/ansible.tf`) gera dinamicamente:
     - `ansible/inventories/production.ini` (com os IPs reais das instâncias e o ProxyCommand configurado).
     - `ansible/inventories/group_vars/all.yml` (com variáveis globais, IPs e URLs do ECR).
   - Playbook unificado `ansible/playbooks/site.yml` que orquestra tudo na sequência correta:
     ```
     docker.yml ──▶ db.yml ──▶ backend.yml ──▶ nginx.yml ──▶ app.yml ──▶ (observability.yml) ──▶ fluentbit.yml
     ```

---

## 2. Como Usar Localmente

### Passo 1: Aplicar a Infraestrutura com Terraform
```bash
cd terraform
terraform init
terraform apply
```
> O Terraform criará a VPC, subnets, EC2s, Load Balancer, ECR e gerará o inventário dinâmico em `ansible/inventories/production.ini`.

### Passo 2: Executar o Ansible Playbook Mestre
```bash
cd ../ansible
ansible-playbook -i inventories/production.ini playbooks/site.yml
```

---

## 3. Configuração do GitHub Actions (CI/CD)

O pipeline `.github/workflows/deploy.yml` está pronto para execução automática.

### Secrets Necessárias no GitHub:
Vá em seu repositório no GitHub: **Settings > Secrets and variables > Actions > New repository secret** e adicione:

| Secret | Descrição |
| :--- | :--- |
| `AWS_ACCESS_KEY_ID` | Chave de acesso da AWS (Learner Lab / IAM User) |
| `AWS_SECRET_ACCESS_KEY` | Chave secreta da AWS |
| `AWS_SESSION_TOKEN` | Token de sessão temporário (obrigatório para AWS Academy) |
| `AWS_REGION` | Região da AWS (ex: `us-east-1`) |
| `SSH_PRIVATE_KEY` | Conteúdo da chave privada SSH (`vokey.pem` ou `Key-All.pem`) |

### Como disparar o Pipeline:
1. **Automático:** A cada `git push` na branch `main`.
2. **Manual (com controle de Observabilidade):**
   - Acesse a aba **Actions** no GitHub.
   - Selecione **CI/CD Pipeline - SGPJ Infrastructure & App**.
   - Clique em **Run workflow**.
   - Marque ou desmarque a opção: `Habilitar EC2 e servicos de Observabilidade?` (permite subir com ou sem a stack de monitoramento).
