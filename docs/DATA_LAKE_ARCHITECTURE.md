# Data Lake Architecture - SGPJ

## Visão Geral

Este documento descreve a arquitetura do Data Lake implementada para o projeto SGPJ, seguindo o padrão **Medallion Architecture** (Bronze → Silver → Gold) com **3 camadas no catálogo Glue** e **2 jobs ETL Glue** (Bronze→Silver, Silver→Gold) para transformação de dados.

---

## Arquitetura das Camadas

### 🥉 Bronze Layer (Raw Zone)
- **Bucket S3**: `sgpj-bronze`
- **Database Glue**: `sgpj_bronze`
- **Crawler**: `sgpj-bronze-crawler`
- **Propósito**: Armazenamento imutável de dados brutos (raw) exatamente como recebidos das fontes
- **Formato**: JSON, CSV, Parquet, Avro (formato original da fonte)
- **Retenção**: Longa (dados históricos imutáveis)
- **Casos de uso**: Auditoria, reprocessamento, debug, compliance

**Exemplos de dados:**
- Logs de aplicação (JSON Lines)
- Dumps de banco de dados (CSV/Parquet)
- Eventos de clickstream (JSON)
- Arquivos de integração (XML, JSON)

---

### 🥈 Silver Layer (Curated Zone)
- **Bucket S3**: `sgpj-silver`
- **Database Glue**: `sgpj_silver`
- **Crawler**: `sgpj-silver-crawler`
- **Job ETL**: `sgpj-bronze-to-silver` (Glue Spark)
- **Propósito**: Dados limpos, validados, enriquecidos e estruturados
- **Formato**: Parquet (otimizado para analytics)
- **Transformações aplicadas:**
  - Limpeza de dados (nulls, duplicatas, outliers)
  - Padronização de tipos e formatos
  - Enriquecimento (joins com dimensões, lookups)
  - Particionamento por data/entidade
  - Schema enforcement/evolution

**Exemplos de dados:**
- Tabelas de fatos (vendas, eventos, transações)
- Dimensões (usuários, produtos, tempo)
- Datasets prontos para BI/ML

---

### 🥇 Gold Layer (Business Zone)
- **Bucket S3**: `sgpj-gold`
- **Database Glue**: `sgpj_gold`
- **Crawler**: `sgpj-gold-crawler`
- **Job ETL**: `sgpj-silver-to-gold` (Glue Spark)
- **Propósito**: Dados agregados, métricas de negócio, dashboards-ready
- **Formato**: Parquet, CSV (para export)
- **Transformações aplicadas:**
  - Agregações pré-calculadas (KPIs, métricas)
  - Wide tables para dashboards
  - Data marts departamentais
  - Feature stores para ML

**Exemplos de dados:**
- Resumo diário de vendas por região
- Métricas de engajamento de usuários
- Relatórios executivos
- Features para modelos de ML

---

## Fluxo de Dados

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   SOURCES   │────▶│   BRONZE    │────▶│   SILVER    │────▶│   GOLD      │
│             │     │  (Raw)      │     │ (Curated)   │     │ (Business)  │
└─────────────┘     └─────────────┘     └─────────────┘     └─────────────┘
                           │                   │                   │
                           ▼                   ▼                   ▼
                    ┌─────────────┐     ┌─────────────┐     ┌─────────────┐
                    │  Crawler    │     │  Crawler    │     │  Crawler    │
                    │  Bronze     │     │  Silver     │     │  Gold       │
                    └─────────────┘     └─────────────┘     └─────────────┘
                           │                   │                   │
                           ▼                   ▼                   ▼
                    ┌─────────────────────────────────────────────────────┐
                    │              AWS Glue Data Catalog                  │
                    │  (sgpj_bronze, sgpj_silver, sgpj_gold)              │
                    └─────────────────────────────────────────────────────┘
                                       │
                    ┌──────────────────┼──────────────────┐
                    ▼                  ▼                  ▼
             ┌─────────────┐    ┌─────────────┐    ┌─────────────┐
             │  Glue Job   │    │  Glue Job   │    │   Athena    │
             │Bronze→Silver│    │Silver→Gold  │    │  / BI Tools │
             └─────────────┘    └─────────────┘    └─────────────┘
                    │                  │
                    ▼                  ▼
             s3://sgpj-      s3://sgpj-
             silver/         gold/
```

---

## Componentes AWS

| Componente | Recurso | Descrição |
|------------|---------|-----------|
| **Storage** | S3 Buckets | 3 buckets com versionamento + criptografia AES256 |
| **Catalog** | Glue Databases | 3 databases (bronze, silver, gold) |
| **Discovery** | Glue Crawlers | 3 crawlers (bronze, silver, gold) - executados sob demanda |
| **ETL** | Glue Jobs | 2 jobs Spark (bronze→silver, silver→gold) |
| **Permissions** | IAM Roles | `sgpj-glue-crawler-role` + `sgpj-glue-job-role` |

---

## Políticas de Segurança

### Criptografia
- **Em repouso**: SSE-S3 (AES256) em todos os buckets
- **Em trânsito**: TLS 1.2+ obrigatório

### Versionamento
- Habilitado em todos os buckets para proteção contra exclusão acidental

### Acesso
- IAM Role específica para Glue Crawlers (`sgpj-glue-crawler-role`)
- IAM Role específica para Glue Jobs (`sgpj-glue-job-role`)
- Princípio de menor privilégio: acesso apenas aos 3 buckets do data lake

---

## Padrões de Nomenclatura

### Buckets S3
```
sgpj-{layer}
Ex: sgpj-bronze, sgpj-silver, sgpj-gold
```

### Databases Glue
```
sgpj_{layer}
Ex: sgpj_bronze, sgpj_silver, sgpj_gold
```

### Crawlers Glue
```
sgpj-{layer}-crawler
Ex: sgpj-bronze-crawler, sgpj-silver-crawler, sgpj-gold-crawler
```

### Glue Jobs
```
sgpj-{source}-to-{target}
Ex: sgpj-bronze-to-silver, sgpj-silver-to-gold
```

### Tabelas (padrão sugerido)
```
{domain}_{entity}_{layer}
Ex: sales_orders_bronze, sales_orders_silver, user_events_silver
```

### Particionamento (padrão sugerido)
```
s3://sgpj-{layer}/{domain}/{entity}/year=YYYY/month=MM/day=DD/
Ex: s3://sgpj-silver/sales/orders/year=2024/month=01/day=15/
```

---

## Execução dos Crawlers

### Via AWS CLI
```bash
# Bronze crawler (processa dados raw)
aws glue start-crawler --name sgpj-bronze-crawler

# Silver crawler (processa dados limpos)
aws glue start-crawler --name sgpj-silver-crawler

# Gold crawler (processa dados agregados)
aws glue start-crawler --name sgpj-gold-crawler
```

### Via Console AWS
1. Acesse AWS Glue > Crawlers
2. Selecione o crawler desejado
3. Clique em "Run crawler"

### Monitoramento
```bash
# Ver status
aws glue get-crawler --name sgpj-bronze-crawler

# Ver métricas no CloudWatch
# Namespace: AWS/Glue
# Métricas: CrawlerRunTime, TablesCreated, TablesUpdated, TablesDeleted
```

---

## Execução dos Jobs ETL

### Via AWS CLI
```bash
# Bronze → Silver
aws glue start-job-run --job-name sgpj-bronze-to-silver

# Silver → Gold
aws glue start-job-run --job-name sgpj-silver-to-gold
```

### Monitoramento de Jobs
```bash
# Ver execuções recentes
aws glue get-job-runs --job-name sgpj-bronze-to-silver --max-results 5

# Ver detalhes de uma execução
aws glue get-job-run --job-name sgpj-bronze-to-silver --run-id <run-id>
```

---

## Consultando com Athena

Após executar os crawlers, as tabelas estão disponíveis no Athena:

```sql
-- Query no Bronze (dados raw)
SELECT * FROM "sgpj_bronze"."events_json" LIMIT 10;

-- Query no Silver (dados limpos)
SELECT event_type, COUNT(*) as total, COUNT(DISTINCT user_id) as unique_users
FROM "sgpj_silver"."events_parquet"
GROUP BY event_type;

-- Query no Gold (métricas de negócio)
SELECT * FROM "sgpj_gold"."daily_metrics"
WHERE event_date >= DATE '2024-01-01'
ORDER BY event_date DESC;
```

---

## Boas Práticas

### Ingestão para Bronze
1. **Não transforme** - salve exatamente como chegou
2. **Particione por data de ingestão** - facilita reprocessamento
3. **Use formatos columnares** (Parquet) quando possível
4. **Metadados**: adicione `_ingestion_timestamp`, `_source_file`

### Processamento Bronze → Silver (Glue Job)
1. **Idempotência** - jobs podem ser reexecutados
2. **Schema evolution** - use `mergeSchema` no Delta/Parquet
3. **Data quality** - valide com Great Expectations ou similar
4. **Particionamento** - por data de evento (não ingestão)

### Silver → Gold (Glue Job)
1. **Pré-agregue** - evite scans full table em dashboards
2. **Materialize views** - crie tabelas wide para BI
3. **Versionamento** - mantenha histórico de KPIs (SCD Type 2)

---

## Estimativa de Custos (us-east-1)

| Recurso | Custo Mensal Estimado |
|---------|----------------------|
| S3 Storage (100GB) | ~$2.30 |
| S3 Requests (1M PUT/GET) | ~$0.50 |
| Glue Crawler (3x, 1h/dia) | ~$22.50 |
| Glue Job (2x, 2h/dia, 2 DPUs) | ~$72.00 |
| Glue Data Catalog (100 tabelas) | ~$1.00 |
| CloudWatch Logs | ~$0.50 |
| **Total** | **~$98.80/mês** |

*Valores aproximados, variam com volume real e tempo de execução dos jobs*

---

## Próximos Passos

1. [ ] Personalizar scripts ETL (`bronze_to_silver.py`, `silver_to_gold.py`) para seu schema
2. [ ] Configurar Lake Formation para governança de acesso
3. [ ] Adicionar Data Quality checks (Great Expectations)
4. [ ] Implementar pipeline de orquestração (Airflow/Step Functions/EventBridge)
5. [ ] Configurar Athena/Redshift Spectrum para query federada
6. [ ] Adicionar alertas CloudWatch para falhas de crawler/job