-- ==============================================================================
-- DDL para criacao das tabelas de logs no AWS Athena / Glue Catalog
-- Database: sgpj_logs_bronze
-- Localizacao: s3://sgpj-bronze/logs/
-- ==============================================================================

CREATE DATABASE IF NOT EXISTS sgpj_logs_bronze
COMMENT 'Database dedicado aos logs brutos da aplicacao (Bronze Tier)';

-- ------------------------------------------------------------------------------
-- 1. Tabela de Logs dos Containers Docker da Aplicacao
-- Particionado por year, month, day, hour (Hive Partitioning)
-- ------------------------------------------------------------------------------
CREATE EXTERNAL TABLE IF NOT EXISTS sgpj_logs_bronze.containers (
  `log` string COMMENT 'Linha de log gerada pela aplicacao / container',
  `stream` string COMMENT 'Fluxo de saida (stdout ou stderr)',
  `time` string COMMENT 'Timestamp ISO8601 gerado pelo Docker',
  `host` string COMMENT 'Instancia EC2 de origem',
  `environment` string COMMENT 'Ambiente de execucao (ex: production)',
  `source_type` string COMMENT 'Origem do coletor (fluentbit)'
)
PARTITIONED BY (
  `year` string,
  `month` string,
  `day` string,
  `hour` string
)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
WITH SERDEPROPERTIES (
  'ignore.malformed.json' = 'true',
  'case.insensitive' = 'true'
)
STORED AS TEXTFILE
LOCATION 's3://sgpj-bronze/logs/containers/'
TBLPROPERTIES (
  'has_encrypted_data'='false',
  'classification'='json',
  'compressionType'='gzip'
);

-- ------------------------------------------------------------------------------
-- 2. Tabela de Logs do Servidor Web Nginx
-- ------------------------------------------------------------------------------
CREATE EXTERNAL TABLE IF NOT EXISTS sgpj_logs_bronze.nginx (
  `remote` string COMMENT 'IP do cliente',
  `host` string COMMENT 'Host do header HTTP',
  `user` string COMMENT 'Usuario autenticado HTTP',
  `time` string COMMENT 'Horario da requisicao',
  `method` string COMMENT 'Metodo HTTP (GET, POST, etc.)',
  `path` string COMMENT 'URI / Rota acessada',
  `code` int COMMENT 'Codigo de status HTTP (200, 404, 500, etc.)',
  `size` int COMMENT 'Tamanho do corpo da resposta em bytes',
  `referer` string COMMENT 'URL de referencia',
  `agent` string COMMENT 'User-Agent do navegador/cliente',
  `level` string COMMENT 'Nivel do log (para logs de erro: warn, error, emerg)',
  `message` string COMMENT 'Mensagem de erro (para logs de erro)',
  `environment` string COMMENT 'Ambiente'
)
PARTITIONED BY (
  `year` string,
  `month` string,
  `day` string,
  `hour` string
)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
WITH SERDEPROPERTIES (
  'ignore.malformed.json' = 'true'
)
STORED AS TEXTFILE
LOCATION 's3://sgpj-bronze/logs/nginx/'
TBLPROPERTIES (
  'classification'='json',
  'compressionType'='gzip'
);

-- ------------------------------------------------------------------------------
-- 3. Tabela de Logs do Sistema Operacional (Syslog & Auth)
-- ------------------------------------------------------------------------------
CREATE EXTERNAL TABLE IF NOT EXISTS sgpj_logs_bronze.os (
  `pri` string COMMENT 'Prioridade do syslog',
  `time` string COMMENT 'Timestamp do evento',
  `host` string COMMENT 'Hostname do servidor',
  `ident` string COMMENT 'Processo / Servico emissor (sshd, sudo, systemd)',
  `pid` string COMMENT 'Process ID',
  `message` string COMMENT 'Mensagem do log do sistema operacional',
  `environment` string COMMENT 'Ambiente'
)
PARTITIONED BY (
  `year` string,
  `month` string,
  `day` string,
  `hour` string
)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
WITH SERDEPROPERTIES (
  'ignore.malformed.json' = 'true'
)
STORED AS TEXTFILE
LOCATION 's3://sgpj-bronze/logs/os/'
TBLPROPERTIES (
  'classification'='json',
  'compressionType'='gzip'
);

-- ==============================================================================
-- Comando para reparar as particoes caso sejam criadas novas pastas no S3:
-- MSCK REPAIR TABLE sgpj_logs_bronze.containers;
-- MSCK REPAIR TABLE sgpj_logs_bronze.nginx;
-- MSCK REPAIR TABLE sgpj_logs_bronze.os;
-- ==============================================================================
