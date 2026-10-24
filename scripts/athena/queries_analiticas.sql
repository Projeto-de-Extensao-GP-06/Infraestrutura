-- ==============================================================================
-- Consultas Analiticas para AWS Athena (Pipeline Dedicado de Logs)
-- Database: sgpj_logs_bronze
-- ==============================================================================

-- 1. Identificar Excecoes e Erros criticos nos Containers da Aplicacao
SELECT 
    host,
    time,
    stream,
    log,
    year,
    month,
    day,
    hour
FROM sgpj_logs_bronze.containers
WHERE regexp_like(log, '(?i)(error|exception|fail|fatal|nullpointer|timeout)')
ORDER BY time DESC
LIMIT 50;

-- 2. Distribuicao de Codigos HTTP no Nginx (Saude da Aplicacao / Erros 4xx e 5xx)
SELECT 
    code AS http_status,
    COUNT(*) AS total_requisicoes,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER (), 2) AS percentual
FROM sgpj_logs_bronze.nginx
WHERE year = '2026'
GROUP BY code
ORDER BY total_requisicoes DESC;

-- 3. Top 10 Rotas Mais Lentas ou Mais Acessadas no Nginx
SELECT 
    method,
    path,
    COUNT(*) AS total_acessos,
    AVG(size) AS media_bytes_resposta
FROM sgpj_logs_bronze.nginx
GROUP BY method, path
ORDER BY total_acessos DESC
LIMIT 10;

-- 4. Auditoria de Seguranca do Sistema Operacional (Tentativas Invalidas de SSH/Sudo)
SELECT 
    host,
    time,
    ident,
    message,
    year,
    month,
    day
FROM sgpj_logs_bronze.os
WHERE regexp_like(message, '(?i)(failed password|invalid user|authentication failure|sudo)')
ORDER BY time DESC
LIMIT 50;

-- 5. Volume de Logs Gerados por Hora (Detectar Picos de Trafego e Anomalias)
SELECT 
    year,
    month,
    day,
    hour,
    COUNT(*) AS total_logs
FROM sgpj_logs_bronze.containers
GROUP BY year, month, day, hour
ORDER BY year DESC, month DESC, day DESC, hour DESC;
