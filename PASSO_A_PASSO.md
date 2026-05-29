# Passo a passo oficial - Nginx neutro com EFS

Este guia segue a arquitetura final oficial:

- Nginx neutro (porta 80) nas instâncias app
- Conteudo e configuracao do Nginx fora da imagem, montados do EFS
- EFS montado em app e backend para volumes compartilhados
- Sem deploy oficial da role app no pipeline

- debug: curl -s https://ifconfig.me/ip;
- Gerar dados no alb: for i in $(seq 1 200); do curl -s -o /dev/null -w "%{http_code}\n" http://alb-app-2096086600.us-east-1.elb.amazonaws.com/; done

---

## 0) Configurar credenciais antes de comecar

Antes de rodar qualquer playbook, preencha os arquivos abaixo com suas proprias credenciais.
**Nao commite esses valores reais no Git.**

### 0.1 Senha do banco de dados — `terraform/terraform.tfvars`

Este arquivo **nao e versionado** (esta no `.gitignore`). Crie-o na pasta `terraform/`:

```hcl
Key-All                    = "Key-All"           # nome do Key Pair na AWS
region                     = "us-east-1"
rds_password               = "SUA_SENHA_DO_BANCO"
rds_db_name                = "sgpj"
rds_username               = "admin"
rds_instance_class         = "db.t3.micro"
rds_allocated_storage      = 20
observability_allowed_cidr = "SEU_IP_PUBLICO/32"  # curl https://ifconfig.me/ip
```

> **Como descobrir seu IP publico:** rode `curl https://ifconfig.me/ip` no terminal.

### 0.2 Alertas por e-mail (SMTP Gmail)

Edite os dois arquivos abaixo substituindo os placeholders:

**`ansible/playbooks/roles/alertmanager/defaults/main.yml`**

```yaml
alertmanager_smtp_from: "SEU_EMAIL@gmail.com"
alertmanager_smtp_user: "SEU_EMAIL@gmail.com"
alertmanager_smtp_password: "SENHA_APP_GMAIL" # ver instrucao abaixo
alertmanager_alert_email: "EMAIL_DESTINO@gmail.com"
```

**`ansible/playbooks/roles/grafana/defaults/main.yml`**

```yaml
grafana_smtp_user: "SEU_EMAIL@gmail.com"
grafana_smtp_password: "SENHA_APP_GMAIL"
grafana_smtp_from_address: "SEU_EMAIL@gmail.com"
grafana_alert_email: "EMAIL_DESTINO@gmail.com"
```

> **Como gerar a App Password do Gmail:**
>
> 1. Acesse [myaccount.google.com/apppasswords](https://myaccount.google.com/apppasswords)
> 2. Selecione "Outro (nome personalizado)" e crie com o nome "Grafana"
> 3. Copie os 16 caracteres gerados (ex: `abcd efgh ijkl mnop`)
> 4. Use esse valor em `smtp_password` (com ou sem espacos, ambos funcionam)
>
> A conta Gmail deve ter **verificacao em duas etapas ativada** para criar App Passwords.

### 0.3 Inventario Ansible — IPs das instancias

O arquivo `ansible/inventories/production.ini` contem os IPs das suas EC2.
A forma mais facil e gera-lo automaticamente apos o `terraform apply` (veja secao 2).

Se preferir preencher manualmente, substitua os placeholders `<IP_...>`:

```ini
[app]
ec2-app-a ansible_host=<IP_APP_A>
ec2-app-b ansible_host=<IP_APP_B>

[observability]
ec2-observability ansible_host=<IP_OBSERVABILITY>
```

> Os IPs publicos das EC2 aparecem na saida do `terraform output` ou no console da AWS.
> Os IPs privados de backend e db (10.0.x.x) nao mudam entre sessoes.

---

Depois de ajustar os arquivos em `infra/terraform`, rode:

```bash
cd infra/terraform
terraform init
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

Conferir outputs principais:

```bash
terraform output
```

## 2) Gerar inventario Ansible automaticamente

Rode apos cada `terraform apply`:

```bash
cd infra/terraform
terraform output -json | py ../scripts/gen_inventory.py > ../ansible/inventories/production.ini
```

Obs.: o script agora usa `efs_dns_name` do Terraform (sem hardcode).

---

Inventarios disponiveis:

Exemplo rapido para usar outro ambiente:

```bash
eval $(ssh-agent -s)
ssh-add ~/.ssh/Key-All.pem

ansible all -m ping -i inventories/production.ini
```

Se estiver no WSL em pasta do OneDrive (/mnt/c/...), pode aparecer aviso de `world writable`.
Isso nao impede o inventario de funcionar, mas faz o Ansible ignorar o `ansible.cfg` local.

Use este comando completo para evitar dependencia do `ansible.cfg`:

# Usar antes eval $(ssh-agent -s) ssh-add ~/.ssh/Key-All.pem

```bash
ansible all -m ping -i inventories/production.ini -u ubuntu --private-key ~/.ssh/Key-All.pem
```

Opcional (mais limpo): trabalhar com o repo dentro do Linux (`~/projetos/...`) em vez de `/mnt/c/...`.

---

## 4) Instalar dependencias do Ansible (opcional)

Agora a instalacao usa arquivo padrao:

```bash
cd infra/ansible
ansible-galaxy collection install -r requirements.yml
```

- Em maquina/runner novo: sim, pelo menos uma vez.
- Em maquina ja preparada: so quando atualizar o `requirements.yml` ou limpar ambiente.

## 5) Aplicar playbooks na ordem correta

### 5.1 Docker + montagem EFS (app e backend)

```bash
cd infra/ansible
ansible-playbook -i inventories/production.ini playbooks/docker.yml

```

Esse playbook:

1. Instala Docker em todos os hosts
2. Monta EFS em app e backend (quando `efs_dns` existe)
3. Cria estrutura padrao no EFS:
   - `/mnt/efs-sgpj/volumes/nginx/html`
   - `/mnt/efs-sgpj/volumes/nginx/conf`
   - `/mnt/efs-sgpj/volumes/backend/uploads`
   - `/mnt/efs-sgpj/volumes/backend/logs`
   - `/mnt/efs-sgpj/volumes/shared`

### 5.2 Nginx neutro (conteudo e conf no EFS)

```bash
cd infra/ansible
ansible-playbook -i inventories/production.ini playbooks/nginx.ymlc
```

Se quiser fazer teste de A/B:

````bash
Esse playbook:

1. Sobe Nginx oficial (`nginx:stable-alpine`) na porta 80
2. Monta `html` do EFS em `/usr/share/nginx/html`
3. Monta `conf` do EFS em `/etc/nginx/conf.d`
4. Cria `default.conf` e `index.html` no EFS apenas se nao existirem

### 5.3 Observabilidade (opcional)

```bash
cd infra/ansible
ansible-playbook -i inventories/production.ini playbooks/observability.yml
```

Portas:

- Prometheus: `9090`
- Grafana: `3001`
- Alertmanager: `9093`
- Loki: `3100` (ingest para Alloy na VPC)
- CloudWatch Exporter: `9106`

Esse playbook agora sobe:

1. Prometheus (metricas)
2. Loki (logs)
3. Alertmanager (roteamento de alertas via SMTP/e-mail)
4. Grafana Alloy em todas as instancias (coleta logs Docker)
5. Node Exporter em todas as instancias (app, backend, db)
6. CloudWatch Exporter no host principal (ALB/RDS/EFS)
7. Grafana com data sources provisionados automaticamente (Prometheus e Loki)

Observacao sobre credenciais AWS (Academy/Vocareum):

- As credenciais expiram a cada ~4 horas.
- O CloudWatch Exporter recebe as credenciais via variaveis de ambiente.
- O Ansible le automaticamente o `~/.aws/credentials` local (WSL) a cada execucao.
- Ao renovar credenciais no portal Vocareum, atualize `~/.aws/credentials` e reaplique.

Observacao sobre alertas por e-mail:

- Os alertas sao enviados via Alertmanager -> SMTP (Gmail).
- Antes de rodar este playbook, preencha as credenciais SMTP — veja **secao 0** deste guia.

### 5.4 Acesso local sem abrir portas no Security Group

Se voce nao liberou `9090` e `3001` no Security Group, use tunel SSH:

```bash
ssh -i ~/.ssh/Key-All.pem -L 9090:localhost:9090 -L 3001:localhost:3001 ubuntu@IP_PUBLICO_APP_A
```

Depois abra no navegador local:

- `http://ip_app:9090`
- `http://ip_app:3001`

### 5.5 Grafana sem dados: por que acontece e como resolver

Se o Grafana abrir mas os paineis estiverem vazios, normalmente falta conectar a fonte de dados.

Se aparecer erro de pagina no Grafana (frontend), tente abrir em guia anonima primeiro.
Em alguns casos, cache/extensoes do navegador quebram a renderizacao da interface.

Passos:

1. Entrar no Grafana (`admin/admin`, se voce nao alterou)
2. Ir em Connections > Data sources
3. Confirmar se aparecem `Prometheus` e `Loki`
4. Se nao aparecerem, rodar novamente `playbooks/observability.yml`

Validacao rapida no Explore/Query:

- Query: `up`
- Resultado esperado: pelo menos 1 serie com valor `1`

Validacao rapida de logs (Explore > data source Loki):

- Query: `{job="docker"}`
- Query (somente nginx): `{job="docker"} |= "nginx"`
- Resultado esperado: linhas de log dos containers

Observacao importante:

- No estado atual, o Prometheus coleta Prometheus, Loki, CloudWatch Exporter e Node Exporter.
- Metricas da AWS podem levar alguns minutos para aparecer apos deploy.

### 5.6 Metricas e alertas como codigo (sem depender da interface)

Este projeto agora provisiona automaticamente:

1. Data sources do Grafana (`Prometheus` e `Loki`) com URLs internas Docker (`http://prometheus:9090`, `http://loki:3100`)
2. Tres dashboards provisionados automaticamente:
   - `Observability Overview` — saude da stack de monitoramento e logs
   - `EC2 Node Exporter` — CPU, memoria, disco, rede e load average por instancia
   - `AWS CloudWatch` — ALB, RDS e EFS
3. Regras de alerta no Prometheus com severidade (critical/high/warning)
4. Alertas para camadas: observability, EC2, ALB, RDS e EFS
5. Roteamento de alertas no Alertmanager para SNS (todos os 15 alertas)
6. Integracao Grafana <-> Alertmanager externo via `GF_UNIFIED_ALERTING_ALERTMANAGER_URL`

Para aplicar/atualizar:

```bash
cd infra/ansible
ansible-playbook -i inventories/production.ini playbooks/observability.yml
```

Validar no Prometheus (localhost:9090):

1. Status > Targets
2. Alerts

Queries de validacao (Prometheus):

- `up`
- `aws_applicationelb_request_count_sum`
- `aws_rds_database_connections_average`
- `aws_efs_percent_iolimit_average`
- `node_memory_MemAvailable_bytes`

### 5.7 Habilitar e-mail via SNS (opcional)

No Terraform (`infra/terraform/terraform.tfvars`):

```hcl
enable_alert_sns = true
alert_email      = "seu-email@exemplo.com"
```

Aplicar:

```bash
cd infra/terraform
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

Confirmar o e-mail enviado pela AWS SNS (subscription confirmation), depois:

```bash
cd infra/terraform
terraform output -json | py ../scripts/gen_inventory.py > ../ansible/inventories/production.ini

cd ../ansible
ansible-playbook -i inventories/production.ini playbooks/observability.yml
```

Alertas configurados para envio por e-mail (todos os 15):

```
PrometheusTargetDown|LokiDown|PrometheusMemoryHigh|ScrapeDurationHigh|
NodeCpuHigh|NodeMemoryLow|NodeDiskLow|
AlbUnhealthyHosts|Alb5xxRateHigh|AlbLatencyHigh|
RdsConnectionsHigh|RdsFreeStorageLow|RdsCpuHigh|RdsFreeableMemoryLow|
EfsIoLimitHigh
```

Tempo estimado do evento ate o e-mail:

| Alerta | for: | Total aprox. |
|---|---|---|
| PrometheusTargetDown | 2m | ~3 min |
| NodeDiskLow | 5m | ~6 min |
| AlbUnhealthyHosts | 2m | ~3 min |
| RdsFreeStorageLow | 5m | ~6 min |

Validar no Grafana (localhost:3001):

1. Dashboards > folder `Observability`
2. Dashboards: `Observability Overview`, `EC2 Node Exporter`, `AWS CloudWatch`
3. Explore com Loki: `{job="docker"} |= "nginx"`

---

## 7) Como alterar a pagina sem rebuild de imagem

Com Nginx neutro, basta alterar arquivos no EFS.

No host app:

- Conteudo: `/mnt/efs-sgpj/volumes/nginx/html/index.html`
- Config: `/mnt/efs-sgpj/volumes/nginx/conf/default.conf`

Exemplo de mudanca:

1. editar `index.html`
2. salvar
3. recarregar Nginx (se alterar apenas html, geralmente nem precisa)

Para aplicar mudanca de configuracao com seguranca:

```bash
cd infra/ansible
ansible app -i inventories/production.ini -m command -a "docker restart nginx"
```

---

## 8) Testes rapidos recomendados

### Teste Docker

```bash
cd infra/ansible
ansible all -i inventories/production.ini -m command -a "docker --version"
```

### Teste mount EFS

```bash
cd infra/ansible
ansible app,backend -i inventories/production.ini -m command -a "mount | grep efs"
```

### Teste container Nginx

```bash
cd infra/ansible
ansible app -i inventories/production.ini -m command -a "docker ps"
```

Obs.: em comando ad-hoc do Ansible, strings com `{{ ... }}` podem ser interpretadas como template Jinja.
Por isso, prefira `docker ps` sem `--format` aqui.

### Teste de arquivos no EFS (host)

```bash
cd infra/ansible
ansible app -i inventories/production.ini -m command -a "ls -la /mnt/efs-sgpj/volumes/nginx/html"
ansible app -i inventories/production.ini -m command -a "ls -la /mnt/efs-sgpj/volumes/nginx/conf"
```

### Teste de arquivos dentro do container Nginx

```bash
cd infra/ansible
ansible app -i inventories/production.ini -m command -a "docker exec nginx ls -la /usr/share/nginx/html"
ansible app -i inventories/production.ini -m command -a "docker exec nginx ls -la /etc/nginx/conf.d"
```

### Teste funcional HTTP

Abra no navegador:

- `http://<ALB_DNS>`

---

## 9) Comandos resumidos (producao)

```bash
cd infra/terraform
terraform init
terraform apply -var-file=terraform.tfvars
terraform output -json | py ../scripts/gen_inventory.py > ../ansible/inventories/production.ini

cd ../ansible
ansible-galaxy collection install -r requirements.yml
ansible all -m ping -i inventories/production.ini
ansible-playbook -i inventories/production.ini playbooks/docker.yml
ansible-playbook -i inventories/production.ini playbooks/nginx.yml
ansible-playbook -i inventories/production.ini playbooks/observability.yml
```
````
