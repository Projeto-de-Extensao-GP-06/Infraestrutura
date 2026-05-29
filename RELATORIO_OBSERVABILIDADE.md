# Relatorio de Observabilidade - Projeto SGPJ Infra

## 1. Visao geral executiva

A stack atual de observabilidade esta funcional mesmo sem backend de aplicacao.
No estado atual, o monitoramento foca em infraestrutura e plataforma:

- Saude da stack (Prometheus, Loki, targets)
- Infra de hosts EC2 (Node Exporter)
- Servicos AWS (ALB, RDS, EFS via CloudWatch Exporter)
- Logs de containers Docker de todas as EC2 (Alloy em todos os hosts -> Loki central)

Isso permite detectar falhas de disponibilidade, saturacao de recursos e degradacoes de performance antes da entrada da aplicacao backend.

## 2. Coleta de logs

### 2.1 Escopo atual

A coleta de logs ocorre por leitura dos arquivos Docker JSON em:

- /var/lib/docker/containers/_/_-json.log

Praticamente, isso significa:

- Cada EC2 com Docker envia seus logs locais para o Loki central
- Inclui logs do Nginx e de outros containers locais (Prometheus, Grafana, Loki, exporters), quando presentes

### 2.2 Papeis dos agentes: Alloy e Node Exporter

**Nao sao redundantes — cada um serve um proposito diferente:**

| Agente            | Funcao                          | O que coleta                                       |
| ----------------- | ------------------------------- | -------------------------------------------------- |
| **Node Exporter** | Metricas de host (kernel Linux) | CPU, memoria, disco, rede — via `/proc` e `/sys`   |
| **Alloy**         | Agente universal de telemetria  | Logs Docker, e no futuro: traces OTLP distribuidos |

Alloy nao substitui Node Exporter para metricas de host — ele nao tem acesso direto ao `/proc` do kernel da forma que o Node Exporter tem. O que o Alloy faz melhor:

- Coletar e encaminhar **logs** de containers Docker para o Loki
- Receber e encaminhar **traces** OTLP (OpenTelemetry) para um backend como Tempo — esse sera o papel central do Alloy quando a rastreabilidade distribuida for implementada
- Pode coletar metricas simples de processo, mas nao substitui o depth do Node Exporter

**Conclusao:** manter ambos. Alloy cuida de logs (e futuramente traces). Node Exporter cuida de metricas de sistema.

## 3. Coleta de metricas

## 3.1 Metricas de plataforma de observabilidade

- up (estado de targets)
- scrape_duration_seconds
- process_resident_memory_bytes (processos monitorados)

Objetivo: validar integridade do proprio sistema de monitoramento.

## 3.2 Metricas de host (Node Exporter)

- CPU (node_cpu_seconds_total)
- Memoria (node_memory_MemAvailable_bytes, node_memory_MemTotal_bytes)
- Disco (node_filesystem_avail_bytes, node_filesystem_size_bytes)

Objetivo: identificar gargalos de recurso em EC2.

## 3.3 Metricas AWS via CloudWatch Exporter

### ALB

- HealthyHostCount (Minimum)
- HTTPCode_Target_5XX_Count (Sum)
- RequestCount (Sum)
- TargetResponseTime (Average)

### RDS

- DatabaseConnections (Average)
- FreeStorageSpace (Average)
- CPUUtilization (Average)
- FreeableMemory (Average)

### EFS

- PercentIOLimit (Average)

Objetivo: correlacionar disponibilidade do balanceamento, saude de banco e pressao de I/O no armazenamento compartilhado.

## 4. Alertas

As regras estao em codigo e classificadas por severidade/layer.

- severidade: critical, high, warning
- layer: observability, ec2, alb, rds, efs

Exemplos de alertas relevantes:

- PrometheusTargetDown (critical)
- AlbUnhealthyHosts (critical)
- RdsFreeStorageLow (critical)
- NodeDiskLow (high)

## 4.1 Roteamento de alertas

Os alertas sao avaliados pelo Prometheus e encaminhados para o **Grafana Unified Alerting**, que roteia via contact point de e-mail (SMTP). Nao ha dependencia de AWS SNS nem de credenciais IAM para notificacoes.

Todos os 15 alertas estao ativos:

```
PrometheusTargetDown | LokiDown | PrometheusMemoryHigh | ScrapeDurationHigh
NodeCpuHigh | NodeMemoryLow | NodeDiskLow
AlbUnhealthyHosts | Alb5xxRateHigh | AlbLatencyHigh
RdsConnectionsHigh | RdsFreeStorageLow | RdsCpuHigh | RdsFreeableMemoryLow | EfsIoLimitHigh
```

### 4.2 Especificacao resumida das metricas dos alertas

Tempo total estimado do evento ate receber o e-mail:

| Alerta               | Expressao                                           | for: | Total aprox. |
| -------------------- | --------------------------------------------------- | ---- | ------------ |
| PrometheusTargetDown | `up == 0`                                           | 2m   | ~3 min       |
| LokiDown             | `up{job="loki"} == 0`                               | 2m   | ~3 min       |
| PrometheusMemoryHigh | `process_resident_memory_bytes > threshold`         | 5m   | ~6 min       |
| ScrapeDurationHigh   | `max_over_time(scrape_duration_seconds[5m]) > 5`    | 5m   | ~6 min       |
| NodeCpuHigh          | `cpu idle < 10%`                                    | 3m   | ~4 min       |
| NodeMemoryLow        | `memory available < 10%`                            | 5m   | ~6 min       |
| NodeDiskLow          | `disco raiz < 15% livre`                            | 5m   | ~6 min       |
| AlbUnhealthyHosts    | `aws_applicationelb_healthy_host_count_minimum < 2` | 2m   | ~3 min       |
| RdsFreeStorageLow    | `aws_rds_free_storage_space_average < 2GB`          | 5m   | ~6 min       |

## 5. Alertas por e-mail via Grafana SMTP

### 5.1 Arquitetura simplificada

O envio de alertas por e-mail e feito diretamente pelo Grafana, sem dependencia de AWS SNS nem de credenciais IAM temporarias:

```
Prometheus -> Grafana Unified Alerting -> SMTP -> E-mail
```

Vantagens em relacao ao modelo anterior (SNS):

- Sem rotacao de credenciais AWS a cada ~4h
- Sem container Alertmanager standalone
- Configuracao centralizada no proprio Grafana
- Funciona com qualquer provedor SMTP (Gmail, Outlook, SendGrid, etc.)

### 5.2 Configuracao necessaria

As variaveis de SMTP sao definidas no inventario Ansible ou em `grafana/defaults/main.yml`:

```yaml
grafana_smtp_enabled: "true"
grafana_smtp_host: "smtp.gmail.com:587"
grafana_smtp_user: "seu-email@gmail.com"
grafana_smtp_password: "sua-app-password" # Google: gerar em myaccount.google.com/apppasswords
grafana_smtp_from_address: "seu-email@gmail.com"
grafana_alert_email: "destino@email.com"
```

### 5.3 Contact point e politica de notificacao

Provisionados automaticamente via Ansible em `/etc/grafana/provisioning/alerting/`:

- `contact-points.yml` — define o receiver de e-mail
- `notification-policies.yml` — define agrupamento, wait e repeat interval

### 5.4 Checklist de habilitacao

1. Definir as vars SMTP no inventario ou nos defaults do role
2. Reaplicar o playbook de observabilidade
3. No Grafana: `Alerting -> Contact points` — verificar se `email-sgpj` aparece
4. Clicar em "Test" no contact point para validar chegada do e-mail
5. Criar ou importar regras de alerta em `Alerting -> Alert rules`

### 5.5 Causas comuns quando nao chega e-mail

- Senha de app do Gmail incorreta (nao usar a senha normal da conta)
- Porta SMTP bloqueada no Security Group da EC2 de observabilidade (porta 587 sainte)
- `grafana_alert_email` nao preenchido nos defaults
- Regra de alerta em Pending e nao em Firing

## 6. Conclusao tecnica

Mesmo sem backend, a arquitetura atual entrega observabilidade de infraestrutura em nivel operacional.
A evolucao recomendada apos entrada do backend e:

- adicionar metricas de aplicacao (APM/business)
- manter coletor de logs em todos os hosts que precisem auditoria
- ajustar thresholds de alerta com base no comportamento real de carga

## 7. Dashboards provisionados

Tres dashboards sao provisionados automaticamente via Ansible na pasta `Observability`:

### 7.1 Observability Overview

Monitora a saude da propria stack de observabilidade:

- **Targets UP**: contagem de todos os targets de scrape do Prometheus (nao so EC2s — ver secao 7.4)
- **Prometheus Active Series**: volume de series no TSDB
- **Prometheus Memory**: memoria do processo Prometheus
- **Scrape Duration**: latencia de coleta por alvo
- **Loki Log Lines / 5m**: taxa de ingestao de logs
- **Nginx Logs**: logs em tempo real via Loki

### 7.2 EC2 Node Exporter

Monitora recursos de todas as instancias EC2:

- **CPU Usage %**: uso de CPU por instancia
- **Memoria Usada %**: percentual de memoria consumida por instancia
- **Disco Usado %**: ocupacao do disco raiz por instancia
- **Rede RX/TX**: trafego de entrada e saida por instancia
- **Memoria Disponivel**: bytes livres por instancia (stat)
- **Load Average (1m)**: carga media do sistema por instancia

### 7.3 AWS CloudWatch

Monitora servicos gerenciados AWS:

- **ALB Requisicoes/s**: volume de requests no balanceador
- **ALB Erros 5xx**: erros de servidor (sem dados quando nao ha erros, esperado)
- **ALB Latencia media**: tempo de resposta em ms
- **RDS CPU %**: utilizacao de CPU do banco
- **RDS Conexoes ativas**: numero de conexoes abertas
- **RDS Armazenamento livre**: espaco disponivel em bytes
- **RDS Memoria disponivel**: freeable memory em bytes
- **EFS IO Limit %**: percentual do limite de I/O do EFS

### 7.4 Por que "Targets UP" mostra 9 com 6 EC2s?

`sum(up)` conta todos os endpoints de scrape do Prometheus, nao apenas instancias EC2:

| Job                   | Targets                                                                       | Qtd   |
| --------------------- | ----------------------------------------------------------------------------- | ----- |
| `node-exporter`       | ec2-app-a, ec2-app-b, ec2-observability, ec2-backend-a, ec2-backend-b, ec2-db | 6     |
| `prometheus`          | localhost:9090                                                                | 1     |
| `loki`                | loki:3100                                                                     | 1     |
| `cloudwatch-exporter` | cloudwatch-exporter:9106                                                      | 1     |
| **Total**             |                                                                               | **9** |

Para ver apenas as EC2s, usar a query: `sum(up{job="node-exporter"})`

### 7.5 Paineis ALB com "No data"

Os paineis **ALB Erros 5xx** e **ALB Latencia media** mostram "No data" quando nao ha trafego real chegando no ALB. Isso e comportamento esperado do CloudWatch:

- `HTTPCode_Target_5XX_Count`: so e publicado quando erros 5xx ocorrem de fato
- `TargetResponseTime`: so e publicado quando requisicoes sao processadas

O painel **ALB Requisicoes/s** sempre mostra dados pois `RequestCount` e publicado mesmo zerado.

**Como gerar trafego para teste:**

1. Obter o DNS do ALB:

```bash
cd terraform && terraform output alb_dns
```

2. Disparar requisicoes via WSL:

```bash
ALB="cole-aqui-o-dns-do-alb"

# Com Apache Benchmark (instalar com: sudo apt install apache2-utils)
ab -n 500 -c 10 http://$ALB/

# Ou so com curl em loop (sem instalacao)
for i in $(seq 1 200); do curl -s -o /dev/null -w "%{http_code}\n" http://$ALB/; done
```

3. Aguardar ~2 minutos (intervalo de coleta do CloudWatch Exporter) e os paineis vao exibir dados.

## 8. Nomes reais das metricas CloudWatch Exporter

O exporter Java gera prefixos a partir do namespace AWS:

| Namespace AWS      | Prefixo Prometheus    |
| ------------------ | --------------------- |
| AWS/ApplicationELB | `aws_applicationelb_` |
| AWS/RDS            | `aws_rds_`            |
| AWS/EFS            | `aws_efs_`            |

Metricas confirmadas em uso:

- `aws_applicationelb_request_count_sum`
- `aws_applicationelb_httpcode_target_5_xx_count_sum`
- `aws_applicationelb_target_response_time_average`
- `aws_rds_cpuutilization_average`
- `aws_rds_database_connections_average`
- `aws_rds_free_storage_space_average`
- `aws_rds_freeable_memory_average`
- `aws_efs_percent_iolimit_average`

## 9. Como ler os paineis (Prometheus e Grafana)

### 7.1 Prometheus Query

- `up`: mostra disponibilidade dos targets.
  - `1` = target acessivel e coletando.
  - `0` = target indisponivel para scrape.
- `up == 0`: lista somente os targets com falha ativa.
- `max_over_time(scrape_duration_seconds[5m]) > 5`: identifica targets com coleta lenta (acima de 5s).

Leitura pratica:

- Se `up == 0` retornar series, os alertas `PrometheusTargetDown` podem ficar em FIRING.
- Se `scrape_duration_seconds` ficar alto por tempo continuo, o alerta `ScrapeDurationHigh` pode disparar.

### 7.3 Grafana Dashboard (Observability Overview)

- Targets UP:
  - Visao executiva da disponibilidade dos principais alvos monitorados.
- Prometheus Active Series:
  - Volume de series ativas no TSDB; crescimento gradual e esperado quando entram novos exporters.
- Prometheus Memory (bytes):
  - Memoria do processo Prometheus; crescimento continuo sem estabilizacao indica necessidade de ajuste.
- Scrape Duration (max 5m):
  - Latencia de coleta por alvo; spikes eventuais sao comuns, persistencia alta exige investigacao.
- Loki Log Lines / 5m:
  - Taxa de ingestao de logs pelo Loki.
- Nginx Logs (Loki):
  - Evidencia operacional (ex.: `GET`, status HTTP, health checks do ELB).

## 10. Leitura do estado atual observado

Com base nas consultas e telas:

- Prometheus e Grafana estao operacionais.
- Loki voltou a ingerir logs e o painel de logs passou a exibir eventos.
- Alertas AWS estao majoritariamente INACTIVE.
- Parte dos alertas de observabilidade pode ficar em FIRING quando algum target estiver `up == 0` ou com scrape lento.

Interpretacao tecnica:

- Esse padrao e comum durante estabilizacao pos-deploy e ajustes de rede/scrape.
- O principal ponto de atencao e reduzir `TargetDown` e `ScrapeDurationHigh` persistentes.

## 11. Como visualizar alertas de forma confiavel

No Prometheus:

1. Abrir `Status -> Alerts`
2. Verificar grupos `core-observability`, `ec2-node-exporter`, `aws-cloudwatch`
3. Priorizar regras em FIRING (vermelho)

Consultas uteis para triagem:

- `up == 0`
- `max_over_time(scrape_duration_seconds[5m]) > 5`
- `ALERTS{alertstate="firing"}`

No Grafana:

1. Abrir `Alerting -> Alert rules`
2. Confirmar regras em estado `Firing`, `Normal` e `Pending`

## 12. Como receber alertas por e-mail via Grafana

### 12.1 Fluxo

```
Prometheus avalia regras
    -> Grafana Unified Alerting (built-in)
    -> Contact point: email-sgpj (SMTP)
    -> E-mail direto
```

### 12.2 Requisitos

1. Vars SMTP preenchidas nos defaults do role Grafana.
2. Playbook de observabilidade reaplicado.
3. Contact point provisionado automaticamente — verificar em `Alerting -> Contact points`.
4. Regras de alerta definidas em `Alerting -> Alert rules` no Grafana.

### 12.3 Como validar envio

1. Grafana `Alerting -> Contact points` -> clicar em **Test** no `email-sgpj`.
2. Confirmar chegada do e-mail (inclusive spam).
3. Verificar se alguma regra esta em **Firing** em `Alerting -> Alert rules`.

### 12.4 Causas comuns quando nao chega e-mail

- App password do Gmail incorreta ou nao gerada.
- Porta 587 (SMTP) bloqueada no Security Group da EC2 de observabilidade.
- `grafana_alert_email` vazio nos defaults.
- Regra em Pending (ainda nao entrou em Firing).
- SMTP desabilitado: verificar `GF_SMTP_ENABLED=true` no container.
