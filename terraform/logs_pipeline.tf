# ------------------------------------------------------------------------------
# Pipeline Dedicado de Logs (AWS Glue + AWS Athena + S3 Bronze Tier)
# ------------------------------------------------------------------------------

# -- 1. Glue Catalog Database Dedicado aos Logs ---------------------------------
resource "aws_glue_catalog_database" "logs_db" {
  name        = "sgpj_logs_bronze"
  description = "Database dedicado exclusivamente para armazenamento e catalogo de logs (Bronze Tier)"
  catalog_id  = data.aws_caller_identity.current.account_id
}

# -- 3. Glue Crawlers Dedicados aos Logs (Opcional - Requer IAM) ----------------
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

# -- 4. AWS Athena Workgroup Dedicado -------------------------------------------
resource "aws_athena_workgroup" "logs_workgroup" {
  name          = "sgpj-logs-analytics"
  description   = "Workgroup do Athena dedicado para consultas analiticas sobre logs"
  force_destroy = true

  configuration {
    enforce_workgroup_configuration    = false
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${local.bronze_bucket}/athena-results/"
      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }

  tags = {
    Pipeline = "logs"
    Purpose  = "analytics"
  }
}

# -- 5. Athena Named Queries (Consultas Salvas Prontas) -------------------------
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

# -- 5.1 Glue Catalog Tables (Athena External Tables) -------------------------
resource "aws_glue_catalog_table" "logs_containers" {
  name          = "containers"
  database_name = aws_glue_catalog_database.logs_db.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "classification"     = "json"
    "compressionType"    = "gzip"
    "has_encrypted_data" = "false"
  }

  partition_keys {
    name = "year"
    type = "string"
  }
  partition_keys {
    name = "month"
    type = "string"
  }
  partition_keys {
    name = "day"
    type = "string"
  }
  partition_keys {
    name = "hour"
    type = "string"
  }

  storage_descriptor {
    location      = "s3://${local.bronze_bucket}/logs/containers/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.IgnoreKeyTextOutputFormat"

    ser_de_info {
      name                  = "json-serde"
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
      parameters = {
        "ignore.malformed.json" = "true"
        "case.insensitive"      = "true"
      }
    }

    columns {
      name = "log"
      type = "string"
    }
    columns {
      name = "stream"
      type = "string"
    }
    columns {
      name = "time"
      type = "string"
    }
    columns {
      name = "host"
      type = "string"
    }
    columns {
      name = "environment"
      type = "string"
    }
    columns {
      name = "source_type"
      type = "string"
    }
  }
}

resource "aws_glue_catalog_table" "logs_nginx" {
  name          = "nginx"
  database_name = aws_glue_catalog_database.logs_db.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "classification"     = "json"
    "compressionType"    = "gzip"
    "has_encrypted_data" = "false"
  }

  partition_keys {
    name = "year"
    type = "string"
  }
  partition_keys {
    name = "month"
    type = "string"
  }
  partition_keys {
    name = "day"
    type = "string"
  }
  partition_keys {
    name = "hour"
    type = "string"
  }

  storage_descriptor {
    location      = "s3://${local.bronze_bucket}/logs/nginx/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.IgnoreKeyTextOutputFormat"

    ser_de_info {
      name                  = "json-serde"
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
      parameters = {
        "ignore.malformed.json" = "true"
      }
    }

    columns {
      name = "remote"
      type = "string"
    }
    columns {
      name = "host"
      type = "string"
    }
    columns {
      name = "user"
      type = "string"
    }
    columns {
      name = "time"
      type = "string"
    }
    columns {
      name = "method"
      type = "string"
    }
    columns {
      name = "path"
      type = "string"
    }
    columns {
      name = "code"
      type = "int"
    }
    columns {
      name = "size"
      type = "int"
    }
    columns {
      name = "referer"
      type = "string"
    }
    columns {
      name = "agent"
      type = "string"
    }
    columns {
      name = "level"
      type = "string"
    }
    columns {
      name = "message"
      type = "string"
    }
    columns {
      name = "environment"
      type = "string"
    }
  }
}

resource "aws_glue_catalog_table" "logs_os" {
  name          = "os"
  database_name = aws_glue_catalog_database.logs_db.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "classification"     = "json"
    "compressionType"    = "gzip"
    "has_encrypted_data" = "false"
  }

  partition_keys {
    name = "year"
    type = "string"
  }
  partition_keys {
    name = "month"
    type = "string"
  }
  partition_keys {
    name = "day"
    type = "string"
  }
  partition_keys {
    name = "hour"
    type = "string"
  }

  storage_descriptor {
    location      = "s3://${local.bronze_bucket}/logs/os/"
    input_format  = "org.apache.hadoop.mapred.TextInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.IgnoreKeyTextOutputFormat"

    ser_de_info {
      name                  = "json-serde"
      serialization_library = "org.openx.data.jsonserde.JsonSerDe"
      parameters = {
        "ignore.malformed.json" = "true"
      }
    }

    columns {
      name = "pri"
      type = "string"
    }
    columns {
      name = "time"
      type = "string"
    }
    columns {
      name = "host"
      type = "string"
    }
    columns {
      name = "ident"
      type = "string"
    }
    columns {
      name = "pid"
      type = "string"
    }
    columns {
      name = "message"
      type = "string"
    }
    columns {
      name = "environment"
      type = "string"
    }
  }
}

# -- 6. Outputs -----------------------------------------------------------------
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
  value       = local.bronze_bucket
}
