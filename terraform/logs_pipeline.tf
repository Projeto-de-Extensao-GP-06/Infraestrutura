# ──────────────────────────────────────────────────────────────────────────────
# Pipeline Dedicado de Logs (AWS Glue + AWS Athena + S3 Bronze Tier)
# ──────────────────────────────────────────────────────────────────────────────

locals {
  athena_results_bucket     = "sgpj-athena-results-${data.aws_caller_identity.current.account_id}"
  athena_results_bucket_arn = "arn:aws:s3:::${local.athena_results_bucket}"
}

# ── 1. Bucket S3 para Resultados das Queries do Athena (via AWS CLI) ───────────
# O provider nativo aws_s3_bucket dispara GetObjectLockConfiguration no refresh,
# operacao bloqueada pelo SCP no AWS Academy. Usar null_resource evita esse bloqueio.
resource "null_resource" "s3_athena_results" {
  triggers = {
    athena_bucket = local.athena_results_bucket
  }

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-Command"]
    command     = <<-EOT
      $ErrorActionPreference = 'Stop'
      $region = '${var.region}'
      $bucket = '${local.athena_results_bucket}'

      aws s3api head-bucket --bucket $bucket 2>$null
      if ($LASTEXITCODE -ne 0) {
        Write-Host "Criando bucket do Athena Results: $bucket..."
        aws s3api create-bucket --bucket $bucket --region $region
      } else {
        Write-Host "Bucket do Athena Results $bucket ja existe."
      }
    EOT
  }
}

# ── 2. Glue Catalog Database Dedicado aos Logs ─────────────────────────────────
resource "aws_glue_catalog_database" "logs_db" {
  name        = "sgpj_logs_bronze"
  description = "Database dedicado exclusivamente para armazenamento e catalogo de logs (Bronze Tier)"
  catalog_id  = data.aws_caller_identity.current.account_id
}

# ── 3. Glue Crawlers Dedicados aos Logs (Opcional - Requer IAM) ────────────────
# No AWS Academy mantem-se false se iam:CreateRole for bloqueado
resource "aws_glue_crawler" "logs_containers_crawler" {
  count         = var.enable_data_lake_iam ? 1 : 0
  name          = "sgpj-crawler-logs-containers"
  role          = aws_iam_role.glue_crawler_role[0].arn
  database_name = aws_glue_catalog_database.logs_db.name
  description   = "Catalogador para logs de containers Docker da aplicacao"

  s3_target {
    path = "s3://${local.bronze_bucket}/logs/containers/"
  }

  schema_change_policy {
    update_behavior = "UPDATE_IN_DATABASE"
    delete_behavior = "LOG"
  }

  recrawl_policy {
    recrawl_behavior = "CRAWL_EVERYTHING"
  }

  configuration = jsonencode({
    Version = 1.0
    CrawlerOutput = {
      Partitions = {
        AddOrUpdateBehavior = "InheritFromTable"
      }
      Tables = {
        AddOrUpdateBehavior = "MergeNewColumns"
      }
    }
  })

  tags = {
    Pipeline = "logs"
    Source   = "containers"
    Tier     = "bronze"
  }
}

resource "aws_glue_crawler" "logs_nginx_crawler" {
  count         = var.enable_data_lake_iam ? 1 : 0
  name          = "sgpj-crawler-logs-nginx"
  role          = aws_iam_role.glue_crawler_role[0].arn
  database_name = aws_glue_catalog_database.logs_db.name
  description   = "Catalogador para logs do Nginx (access e error)"

  s3_target {
    path = "s3://${local.bronze_bucket}/logs/nginx/"
  }

  schema_change_policy {
    update_behavior = "UPDATE_IN_DATABASE"
  }

  recrawl_policy {
    recrawl_behavior = "CRAWL_EVERYTHING"
  }

  configuration = jsonencode({
    Version = 1.0
    CrawlerOutput = {
      Partitions = {
        AddOrUpdateBehavior = "InheritFromTable"
      }
      Tables = {
        AddOrUpdateBehavior = "MergeNewColumns"
      }
    }
  })

  tags = {
    Pipeline = "logs"
    Source   = "nginx"
    Tier     = "bronze"
  }
}

resource "aws_glue_crawler" "logs_os_crawler" {
  count         = var.enable_data_lake_iam ? 1 : 0
  name          = "sgpj-crawler-logs-os"
  role          = aws_iam_role.glue_crawler_role[0].arn
  database_name = aws_glue_catalog_database.logs_db.name
  description   = "Catalogador para logs do Sistema Operacional (syslog e auth)"

  s3_target {
    path = "s3://${local.bronze_bucket}/logs/os/"
  }

  schema_change_policy {
    update_behavior = "UPDATE_IN_DATABASE"
  }

  recrawl_policy {
    recrawl_behavior = "CRAWL_EVERYTHING"
  }

  configuration = jsonencode({
    Version = 1.0
    CrawlerOutput = {
      Partitions = {
        AddOrUpdateBehavior = "InheritFromTable"
      }
      Tables = {
        AddOrUpdateBehavior = "MergeNewColumns"
      }
    }
  })

  tags = {
    Pipeline = "logs"
    Source   = "os"
    Tier     = "bronze"
  }
}

# ── 4. AWS Athena Workgroup Dedicado ───────────────────────────────────────────
resource "aws_athena_workgroup" "logs_workgroup" {
  name        = "sgpj-logs-analytics"
  description = "Workgroup do Athena dedicado para consultas analiticas sobre logs"

  configuration {
    enforce_workgroup_configuration    = false
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${local.athena_results_bucket}/logs-queries/"
      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }

  depends_on = [null_resource.s3_athena_results]

  tags = {
    Pipeline = "logs"
    Purpose  = "analytics"
  }
}

# ── 5. Athena Named Queries (Consultas Salvas Prontas) ─────────────────────────
resource "aws_athena_named_query" "query_containers_errors" {
  name        = "logs_containers_erros_e_excecoes"
  workgroup   = aws_athena_workgroup.logs_workgroup.id
  database    = aws_glue_catalog_database.logs_db.name
  description = "Filtra erros, falhas e stack traces nos logs de containers"

  query = <<-SQL
    SELECT 
      host,
      time,
      stream,
      log,
      year,
      month,
      day
    FROM sgpj_logs_bronze.containers
    WHERE regexp_like(log, '(?i)(error|exception|fail|fatal|warn)')
    ORDER BY time DESC
    LIMIT 100;
  SQL
}

resource "aws_athena_named_query" "query_nginx_status_codes" {
  name        = "logs_nginx_status_distribuicao"
  workgroup   = aws_athena_workgroup.logs_workgroup.id
  database    = aws_glue_catalog_database.logs_db.name
  description = "Agrupamento de status HTTP no Nginx para identificar erros 4xx e 5xx"

  query = <<-SQL
    SELECT 
      code AS http_status,
      count(*) AS total_requisicoes
    FROM sgpj_logs_bronze.nginx
    GROUP BY code
    ORDER BY total_requisicoes DESC;
  SQL
}

resource "aws_athena_named_query" "query_nginx_top_urls" {
  name        = "logs_nginx_top_rotas_acessadas"
  workgroup   = aws_athena_workgroup.logs_workgroup.id
  database    = aws_glue_catalog_database.logs_db.name
  description = "Lista as rotas mais requisitadas no Nginx"

  query = <<-SQL
    SELECT 
      method,
      path,
      count(*) AS total_acessos
    FROM sgpj_logs_bronze.nginx
    GROUP BY method, path
    ORDER BY total_acessos DESC
    LIMIT 20;
  SQL
}

resource "aws_athena_named_query" "query_os_auth_failures" {
  name        = "logs_os_auditoria_falhas_ssh"
  workgroup   = aws_athena_workgroup.logs_workgroup.id
  database    = aws_glue_catalog_database.logs_db.name
  description = "Auditoria de tentativas invalidas de login ou falhas de seguranca no SO"

  query = <<-SQL
    SELECT 
      host,
      time,
      ident,
      message,
      year,
      month,
      day
    FROM sgpj_logs_bronze.os
    WHERE regexp_like(message, '(?i)(failed|invalid|denied|unauthorized)')
    ORDER BY time DESC
    LIMIT 100;
  SQL
}

# ── 6. Outputs ─────────────────────────────────────────────────────────────────
output "logs_database_name" {
  description = "Nome do Database Glue exclusivo para Logs"
  value       = aws_glue_catalog_database.logs_db.name
}

output "athena_logs_workgroup_name" {
  description = "Nome do Workgroup Athena para Logs"
  value       = aws_athena_workgroup.logs_workgroup.name
}

output "athena_results_bucket" {
  description = "Bucket S3 com os resultados do Athena"
  value       = local.athena_results_bucket
}
