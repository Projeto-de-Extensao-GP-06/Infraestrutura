# Relatório de Observabilidade & Telemetria — SGPJ Infra

---

## 1. Visão Geral Executiva

A infraestrutura do projeto **SGPJ** adota uma estratégia moderna de observabilidade híbrida, dividida em dois pilares complementares:

1. **Observabilidade Operacional em Tempo Real (Hot Storage):**
   - **Métricas:** Prometheus + Node Exporter em todas as 6 EC2s + CloudWatch Exporter (ALB/EFS).
   - **Logs ao Vivo:** Grafana Alloy raspando stdout/stderr dos containers Docker diretamente para o Grafana Loki.
   - **Visualização e Alertas:** Grafana (porta `3001`) com dashboards pré-provisionados e notificações por e-mail via SMTP.

2. **Log Analytics & Data Lake de Auditoria (Cold Storage):**
   - **Coletor Nativo:** Fluent Bit rodando como serviço nativo `systemd` em todas as instâncias EC2.
   - **Destino:** Amazon S3 Bronze Tier (`s3://sgpj-bronze-<account-id>/logs/`) particionado em Hive (`year=.../month=.../day=.../hour=...`).
   - **Catálogo & Queries Analíticas:** AWS Glue Catalog Database (`sgpj_logs_bronze`) e AWS Athena (`sgpj-logs-analytics`) para consultas analíticas em lote via SQL padrão.

```
┌────────────────────────────────────────────────────────────────────────┐
│                   FONTES DE TELEMETRIA (EC2s)                          │
│     ec2-app-a/b  │  ec2-backend-a/b  │  ec2-db  │  ec2-observability   │
└────────┬──────────────────────┬────────────────────────┬───────────────┘
         │ (Métricas :9100)     │ (Logs Tempo Real)      │ (Logs Auditoria Gzip)
         ▼                      ▼                        ▼
  ┌──────────────┐       ┌──────────────┐         ┌──────────────┐
  │  Prometheus  │       │ Grafana Loki │         │  Fluent Bit  │
  │   (:9090)    │       │   (:3100)    │         │ (Systemd)    │
  └──────┬───────┘       └──────┬───────┘         └──────┬───────┘
         │                      │                        │ (s3:PutObject)
         ▼                      ▼                        ▼
  ┌─────────────────────────────────────┐         ┌──────────────┐
  │       GRAFANA DASHBOARDS            │         │  S3 BRONZE   │
  │    (Visualização Unificada :3001)   │         │ (Hive Part.) │
  └─────────────────────────────────────┘         └──────┬───────┘
                                                         │
                                                         ▼
                                                  ┌──────────────┐
                                                  │  AWS ATHENA  │
                                                  │ (SQL Queries)│
                                                  └──────────────┘
```

---

## 2. Coleta de Logs: Dois Pilares Complementares

| Característica | Grafana Loki (via Grafana Alloy) | Fluent Bit (via Amazon S3 + Athena) |
|---|---|---|
| **Propósito** | Debugging imediato, alertas ao vivo e troubleshooting rápido | Retenção de longo prazo, auditoria e consultas analíticas pesadas |
| **Destino** | Volume local do Loki na `ec2-observability` | Amazon S3 Bronze Tier (`sgpj-bronze-<id>`) |
| **Formato** | Índices de rótulos (streams) no Loki | Arquivos `.json.gz` particionados por ano/mês/dia/hora |
| **Mecanismo de Busca** | LogQL no painel Explore do Grafana | Consultas SQL ANSI padrão no AWS Athena |
| **Retenção** | Efêmera / Média (otimizada para os últimos dias) | Permanente / Fria (baixo custo no S3) |

---

## 3. Métricas Coletadas

### 3.1 Métricas de Infraestrutura (Node Exporter — Porta 9100)
Coletadas a cada 15 segundos em todos os 6 nós:
- **CPU:** `node_cpu_seconds_total` (cálculo de % de uso e iowait).
- **Memória:** `node_memory_MemAvailable_bytes`, `node_memory_MemTotal_bytes`.
- **Disco:** `node_filesystem_avail_bytes`, `node_filesystem_size_bytes` (volume raiz e montagens EFS).
- **Rede:** `node_network_receive_bytes_total`, `node_network_transmit_bytes_total`.

### 3.2 Métricas de Serviços AWS (CloudWatch Exporter — Porta 9106)
- **Application Load Balancer (ALB):**
  - `aws_applicationelb_request_count_sum`: Total de requisições por minuto.
  - `aws_applicationelb_target_response_time_average`: Tempo médio de resposta dos nós da aplicação.
  - `aws_applicationelb_httpcode_target_5_xx_count_sum`: Ocorrência de erros de servidor.
  - `aws_applicationelb_healthy_host_count_minimum`: Quantidade de instâncias saudáveis no Target Group.
- **Elastic File System (EFS):**
  - `aws_efs_percent_iolimit_average`: Consumo do limite de I/O do armazenamento persistente compartilhado.

---

## 4. Regras de Alerta Pré-Configuradas

| Alerta | Expressão PromQL | For | Severidade |
|---|---|---|---|
| **InstanceDown** | `up{job="node-exporter"} == 0` | 1m | Crítica (Host inacessível) |
| **NodeCpuHigh** | `(1 - avg by(instance)(rate(node_cpu_seconds_total{mode="idle"}[5m]))) * 100 > 85` | 3m | Alta (Sobrecarga de CPU) |
| **NodeMemoryLow** | `(node_memory_MemAvailable_bytes / node_memory_MemTotal_bytes) * 100 < 10` | 5m | Alta (Esgotamento de RAM) |
| **NodeDiskLow** | `(node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes) * 100 < 15` | 5m | Alta (Disco quase cheio) |
| **AlbUnhealthyHosts** | `aws_applicationelb_healthy_host_count_minimum < 2` | 2m | Crítica (Perda de redundância no ALB) |

---

## 5. Consultas Analíticas Prontas no AWS Athena

No AWS Athena, com o Workgroup `sgpj-logs-analytics` selecionado, as seguintes consultas já estão salvas e prontas para execução imediata:

### 5.1 Erros e Exceções nos Containers
```sql
SELECT host, time, stream, log, year, month, day
FROM sgpj_logs_bronze.containers
WHERE regexp_like(log, '(?i)(error|exception|fail|fatal|warn)')
ORDER BY time DESC
LIMIT 100;
```

### 5.2 Distribuição de Códigos HTTP no Nginx
```sql
SELECT code AS http_status, count(*) AS total_requisicoes
FROM sgpj_logs_bronze.nginx
GROUP BY code
ORDER BY total_requisicoes DESC;
```

### 5.3 Rotas Mais Acessadas da Aplicação
```sql
SELECT method, path, count(*) AS total_acessos
FROM sgpj_logs_bronze.nginx
GROUP BY method, path
ORDER BY total_acessos DESC
LIMIT 20;
```

### 5.4 Auditoria de Tentativas Inválidas de SSH
```sql
SELECT host, time, ident, message, year, month, day
FROM sgpj_logs_bronze.os
WHERE regexp_like(message, '(?i)(failed|invalid|denied|unauthorized)')
ORDER BY time DESC
LIMIT 100;
```

---

## 6. Dashboards Provisionados no Grafana

O Grafana (`http://<IP_OBSERVABILITY>:3001`) já sobe com 3 dashboards estruturados:

1. **Observability Overview:** Saúde dos servidores de métricas, contagem de targets `up`, uso de memória do Prometheus e ingestão do Loki.
2. **EC2 Node Exporter:** Visão detalhada de consumo de hardware (CPU, RAM, Disco, Load Average) para cada uma das instâncias da infraestrutura.
3. **AWS CloudWatch:** Gráficos de telemetria do ALB (taxa de requests, latência, erros 5xx) e taxas de I/O do EFS.
