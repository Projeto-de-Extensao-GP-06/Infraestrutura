# Arquitetura de Telemetria, Logs e Auditoria — SGPJ

Este documento descreve detalhadamente a arquitetura de coleta, roteamento, armazenamento e análise de telemetria e logs da infraestrutura **SGPJ**, esclarecendo a divisão de responsabilidades entre a pilha de **Observabilidade Operacional em Tempo Real** (Loki/Grafana) e o **Data Lake Analítico de Logs** (S3 Bronze/Glue/Athena).

---

## 1. Visão Geral da Estratégia de Dados e Logs

O projeto adota o modelo de separação em duas frentes complementares:

1. **Hot Storage (Operação em Tempo Real)**:
   - **Objetivo**: Resposta rápida a incidentes, alertas e caça a erros ao vivo durante execução ou deploy.
   - **Mecanismo**: Grafana Loki indexando labels de containers Docker, visualizado no Grafana.
   - **Retenção**: Curta (dados mantidos no disco volátil da EC2 de Observabilidade).

2. **Cold Storage (Auditoria, Conformidade e Análise Histórica)**:
   - **Objetivo**: Retenção prolongada e de baixo custo, conformidade com políticas de auditoria e capacidade de executar consultas analíticas profundas em SQL.
   - **Mecanismo**: Fluent Bit compactando os eventos em Gzip e gravando em formato de partições Hive no Amazon S3 (Bronze Tier), catalogado no AWS Glue e consultável no AWS Athena.
   - **Retenção**: Longa (armazenamento de baixo custo em bucket S3).

---

## 2. Matriz de Destino por Tipo de Log

| Origem do Log | Tag no Fluent Bit | Formato / Parser | Destino Hot (Loki) | Destino Cold (S3 Bronze) | Caminho S3 Partitioned |
|---|---|---|:---:|:---:|---|
| **Containers Docker** (Nginx SPA + Backend API) | `containers.*` | Docker JSON | ✅ Sim | ✅ Sim | `logs/containers/year=%Y/month=%m/day=%d/hour=%H/` |
| **Nginx Access & Error** (Host / Reverse Proxy) | `nginx.access`<br>`nginx.error` | Nginx regex | ❌ Não | ✅ Sim | `logs/nginx/year=%Y/month=%m/day=%d/hour=%H/` |
| **Sistema Operacional** (Syslog do Linux) | `os.syslog` | RFC3164 Syslog | ❌ Não | ✅ Sim | `logs/os/year=%Y/month=%m/day=%d/hour=%H/` |
| **Segurança & SSH** (Auth log) | `os.auth` | Texto livre / Auth | ❌ Não | ✅ Sim | `logs/os/year=%Y/month=%m/day=%d/hour=%H/` |

> [!NOTE]
> O único tipo de log compartilhado entre os dois caminhos é o de **Containers da Aplicação**, pois é o ponto central onde tanto o desenvolvedor em plantão precisa ver a exceção ao vivo quanto a equipe precisa auditar falhas do passado.

---

## 3. Diagrama do Fluxo de Telemetria

```mermaid
flowchart TD
    subgraph Nodes["Nós do Cluster (ec2-app-a/b, ec2-backend-a/b, ec2-db)"]
        CL["Logs de Containers Docker (/var/lib/docker/containers/*)"]
        NL["Logs do Servidor Nginx (/var/log/nginx/*)"]
        SL["Logs do Sistema (/var/log/syslog & auth.log)"]
        FB["Fluent Bit (Daemon Nativo Systemd)"]
        NE["Node Exporter (:9100)"]
    end

    CL -->|Tag: containers.*| FB
    NL -->|Tag: nginx.*| FB
    SL -->|Tag: os.*| FB

    subgraph Obs["EC2 Observability (Tempo Real - Hot Storage)"]
        Prom["Prometheus (:9090)"]
        Loki["Grafana Loki (:3100)"]
        Graf["Grafana Dashboards (:3001)"]
        
        NE -->|Pull Métricas| Prom
        Loki -->|LogQL| Graf
        Prom -->|PromQL| Graf
    end

    subgraph DL["AWS Data Lake & Analytics (Histórico - Cold Storage)"]
        S3["Amazon S3: s3://sgpj-bronze-<account>/logs/
        ├── /containers/ (Hive year/month/day/hour)
        ├── /nginx/ (Hive year/month/day/hour)
        └── /os/ (Hive year/month/day/hour)"]

        Glue["AWS Glue Data Catalog
        Database: sgpj_logs_bronze
        Crawlers: containers, nginx, os"]

        Athena["AWS Athena (SQL)
        Workgroup: sgpj-logs-analytics"]

        S3 --> Glue
        Glue --> Athena
    end

    FB -.->|HTTP POST /loki/api/v1/push (se habilitado)| Loki
    FB ==>|s3:PutObject (Gzip streaming)| S3
```

---

## 4. Coleta com Fluent Bit

O agente **Fluent Bit** é instalado de forma padronizada via Ansible (`roles/fluentbit`) em todas as 6 instâncias do ambiente como um serviço gerenciado pelo `systemd`.

### 4.1 Enriquecimento Automático
Antes de entregar qualquer log para a rede ou para a AWS, o Fluent Bit aplica metadados locais através do filtro `record_modifier`:
- `host`: Nome da máquina de onde partiu o log (ex: `ec2-app-a`, `ec2-backend-b`).
- `environment`: `production`.
- `source_type`: `fluentbit`.

### 4.2 Entrega Otimizada no S3
Para não sobrecarregar o bucket com milhões de requisições de poucos bytes:
- **Compressão**: `gzip` nativo no envio.
- **Thresholds de Envio**: Os arquivos são descarregados a cada 5MB acumulados (`total_file_size 5M`) ou a cada 60 segundos (`upload_timeout 60s`).
- **Particionamento Hive**: Organizado automaticamente por chaves de data/hora (`year=%Y/month=%m/day=%d/hour=%H/`), viabilizando que o Athena e o Glue leiam apenas os diretórios requisitados (reduzindo custo de scan).

---

## 5. Análise Analítica com AWS Athena

Com o Glue catalogando os diretórios do bucket Bronze (`sgpj_logs_bronze`), o AWS Athena permite consultas diretas em SQL sem necessidade de subir servidores de banco de dados para os logs.

### 5.1 Exemplos de Consultas Analíticas Úteis

#### Erros HTTP agrupados por status (Nginx):
```sql
SELECT 
    status, 
    count(*) as total_requests,
    host
FROM "sgpj_logs_bronze"."nginx"
WHERE year = '2026' AND month = '10'
GROUP BY status, host
ORDER BY total_requests DESC;
```

#### Rastreamento de falhas e exceptions de containers do Backend:
```sql
SELECT 
    log, 
    host, 
    date_parse(time, '%Y-%m-%dT%H:%i:%s.%fZ') as data_evento
FROM "sgpj_logs_bronze"."containers"
WHERE log LIKE '%Exception%' OR log LIKE '%ERROR%'
ORDER BY data_evento DESC
LIMIT 50;
```

#### Auditoria de segurança: tentativas de acesso SSH (Auth Log):
```sql
SELECT 
    log,
    host
FROM "sgpj_logs_bronze"."os"
WHERE log LIKE '%sshd%' AND (log LIKE '%Failed password%' OR log LIKE '%Accepted%')
LIMIT 100;
```

---

## 6. FAQ Arquitetural

### 1. "Por que não enviar todo o syslog e auth.log para o Loki?"
O Loki foi dimensionado para telemetria de aplicação. Enviar logs massivos de sistema operacional aumentaria desnecessariamente o consumo de CPU/Memória na instância EC2 de Observabilidade (`t3.small`). O S3 oferece durabilidade de 11 noves (99.999999999%) com custo insignificante por gigabyte.

### 2. "Por que não consultar tudo no Athena em vez de usar o Grafana?"
O Athena é voltado para consultas analíticas em lote (batch queries) sobre volumes massivos de arquivos. Cada query leva de 2 a 15 segundos para escanear os dados. Para alertas em tempo real e visualização de dashboards dinâmicos (auto-refresh de 5 segundos), o Loki integrado ao Grafana oferece latência milissegunda.
