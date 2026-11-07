# ── Data Lake S3 Buckets (Bronze, Silver, Gold) ────────────────────────────────
# Nomes incluem account_id para garantir unicidade global no S3.
#
# IMPORTANTE (AWS Academy): O provider aws_s3_bucket chama GetObjectLockConfiguration
# durante o refresh, operação bloqueada pelo SCP da organização do Academy.
# Solução: usar null_resource + AWS CLI para criar e configurar os buckets.
# ARNs são calculados via locals (formato determinístico — não precisamos do provider).

data "aws_caller_identity" "current" {}

locals {
  account_id = data.aws_caller_identity.current.account_id

  bronze_bucket = "sgpj-bronze-${local.account_id}"
  silver_bucket = "sgpj-silver-${local.account_id}"
  gold_bucket   = "sgpj-gold-${local.account_id}"

  # ARNs calculados sem depender do recurso aws_s3_bucket
  bronze_bucket_arn = "arn:aws:s3:::${local.bronze_bucket}"
  silver_bucket_arn = "arn:aws:s3:::${local.silver_bucket}"
  gold_bucket_arn   = "arn:aws:s3:::${local.gold_bucket}"
}

# ── Criação e configuração dos buckets via AWS CLI ─────────────────────────────
# null_resource não faz refresh — nunca chama GetObjectLockConfiguration.
resource "null_resource" "s3_data_lake" {
  triggers = {
    bronze_bucket = local.bronze_bucket
    silver_bucket = local.silver_bucket
    gold_bucket   = local.gold_bucket
  }

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-Command"]
    command     = <<-EOT
      $ErrorActionPreference = 'Continue'
      if (Test-Path variable:PSNativeCommandUseErrorActionPreference) {
        $PSNativeCommandUseErrorActionPreference = $false
      }
      $region  = 'us-east-1'
      $buckets = @('${local.bronze_bucket}', '${local.silver_bucket}', '${local.gold_bucket}')

      # Cria arquivo temporario com JSON de criptografia e formata path com barras normais para o AWS CLI
      $encFile = [System.IO.Path]::GetTempFileName()
      Set-Content -Path $encFile -Value '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":false}]}'
      $encFilePath = $encFile.Replace('\', '/')

      try {
        foreach ($bucket in $buckets) {
          Write-Host ">>> Configurando bucket: $bucket"

          # Verifica se o bucket ja existe antes de criar (usa cmd para evitar NativeCommandError do PowerShell em 404)
          $null = & cmd /c "aws s3api head-bucket --bucket $bucket 2>nul"
          if ($LASTEXITCODE -ne 0) {
            Write-Host "Criando bucket $bucket..."
            aws s3api create-bucket --bucket $bucket --region $region
            if ($LASTEXITCODE -ne 0) { throw "Falha ao criar bucket $bucket" }
          } else {
            Write-Host "Bucket $bucket ja existe, pulando criacao."
          }

          # Habilita versionamento
          Write-Host "Habilitando versionamento em $bucket..."
          aws s3api put-bucket-versioning --bucket $bucket --versioning-configuration Status=Enabled
          if ($LASTEXITCODE -ne 0) { throw "Falha no versionamento de $bucket" }

          # Habilita criptografia AES256
          Write-Host "Habilitando criptografia em $bucket..."
          aws s3api put-bucket-encryption --bucket $bucket --server-side-encryption-configuration "file://$encFilePath"
          if ($LASTEXITCODE -ne 0) { throw "Falha na criptografia de $bucket" }

          Write-Host ">>> Bucket $bucket OK"
        }
      } finally {
        if (Test-Path $encFile) { Remove-Item $encFile -Force }
      }

      Write-Host ">>> Todos os buckets configurados com sucesso"
    EOT
  }
}

# ── IAM Role for Glue Crawlers ─────────────────────────────────────────────────
# Protegido por enable_data_lake_iam (AWS Academy bloqueia iam:CreateRole)
data "aws_iam_policy_document" "glue_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "glue_crawler_role" {
  count              = var.enable_data_lake_iam ? 1 : 0
  name               = "sgpj-glue-crawler-role"
  assume_role_policy = data.aws_iam_policy_document.glue_assume_role.json
  tags               = { Name = "sgpj-glue-crawler-role" }
}

data "aws_iam_policy_document" "glue_crawler_policy" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]
    # Usa locals em vez de aws_s3_bucket.*.arn
    resources = [
      local.bronze_bucket_arn,
      "${local.bronze_bucket_arn}/*",
      local.silver_bucket_arn,
      "${local.silver_bucket_arn}/*",
      local.gold_bucket_arn,
      "${local.gold_bucket_arn}/*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "glue:*",
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "glue_crawler_policy" {
  count  = var.enable_data_lake_iam ? 1 : 0
  name   = "sgpj-glue-crawler-policy"
  role   = aws_iam_role.glue_crawler_role[0].id
  policy = data.aws_iam_policy_document.glue_crawler_policy.json
}

# ── Glue Databases ─────────────────────────────────────────────────────────────
resource "aws_glue_catalog_database" "bronze_db" {
  name        = "sgpj_bronze"
  description = "Bronze layer database for raw data"
  catalog_id  = data.aws_caller_identity.current.account_id
}

resource "aws_glue_catalog_database" "silver_db" {
  name        = "sgpj_silver"
  description = "Silver layer database for cleaned/transformed data"
  catalog_id  = data.aws_caller_identity.current.account_id
}

resource "aws_glue_catalog_database" "gold_db" {
  name        = "sgpj_gold"
  description = "Gold layer database for aggregated/business-ready data"
  catalog_id  = data.aws_caller_identity.current.account_id
}

# ── Glue Crawlers ──────────────────────────────────────────────────────────────
# Só criados quando enable_data_lake_iam = true (requer IAM role criada)
resource "aws_glue_crawler" "bronze_crawler" {
  count         = var.enable_data_lake_iam ? 1 : 0
  name          = "sgpj-bronze-crawler"
  role          = aws_iam_role.glue_crawler_role[0].arn
  database_name = aws_glue_catalog_database.bronze_db.name
  description   = "Crawler for bronze layer raw data"

  s3_target {
    path = "s3://${local.bronze_bucket}/"
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
    }
  })

  tags = {
    Name        = "sgpj-bronze-crawler"
    Environment = "data-lake"
    Layer       = "bronze"
  }
}

resource "aws_glue_crawler" "silver_crawler" {
  count         = var.enable_data_lake_iam ? 1 : 0
  name          = "sgpj-silver-crawler"
  role          = aws_iam_role.glue_crawler_role[0].arn
  database_name = aws_glue_catalog_database.silver_db.name
  description   = "Crawler for silver layer cleaned data"

  s3_target {
    path = "s3://${local.silver_bucket}/"
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
    }
  })

  tags = {
    Name        = "sgpj-silver-crawler"
    Environment = "data-lake"
    Layer       = "silver"
  }
}

resource "aws_glue_crawler" "gold_crawler" {
  count         = var.enable_data_lake_iam ? 1 : 0
  name          = "sgpj-gold-crawler"
  role          = aws_iam_role.glue_crawler_role[0].arn
  database_name = aws_glue_catalog_database.gold_db.name
  description   = "Crawler for gold layer aggregated data"

  s3_target {
    path = "s3://${local.gold_bucket}/"
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
    }
  })

  tags = {
    Name        = "sgpj-gold-crawler"
    Environment = "data-lake"
    Layer       = "gold"
  }
}

# ── IAM Role for Glue ETL Jobs ──────────────────────────────────────────────────
data "aws_iam_policy_document" "glue_job_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "glue_job_role" {
  count              = var.enable_data_lake_iam ? 1 : 0
  name               = "sgpj-glue-job-role"
  assume_role_policy = data.aws_iam_policy_document.glue_job_assume_role.json
  tags               = { Name = "sgpj-glue-job-role" }
}

data "aws_iam_policy_document" "glue_job_policy" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]
    resources = [
      local.bronze_bucket_arn,
      "${local.bronze_bucket_arn}/*",
      local.silver_bucket_arn,
      "${local.silver_bucket_arn}/*",
      local.gold_bucket_arn,
      "${local.gold_bucket_arn}/*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "glue:*",
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "s3:GetObject",
      "s3:PutObject"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "glue_job_policy" {
  count  = var.enable_data_lake_iam ? 1 : 0
  name   = "sgpj-glue-job-policy"
  role   = aws_iam_role.glue_job_role[0].id
  policy = data.aws_iam_policy_document.glue_job_policy.json
}

# ── Glue ETL Job: Bronze → Silver ───────────────────────────────────────────────
resource "aws_glue_job" "bronze_to_silver" {
  count       = var.enable_data_lake_iam ? 1 : 0
  name        = "sgpj-bronze-to-silver"
  description = "ETL job to transform bronze raw data to silver curated format"
  role_arn    = aws_iam_role.glue_job_role[0].arn

  command {
    name            = "glueetl"
    script_location = "s3://${local.silver_bucket}/scripts/bronze_to_silver.py"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-metrics"                   = ""
    "--enable-spark-ui"                  = "true"
    "--spark-event-logs-path"            = "s3://${local.silver_bucket}/logs/spark/"
    "--TempDir"                          = "s3://${local.silver_bucket}/tmp/"
    "--source_bucket"                    = local.bronze_bucket
    "--target_bucket"                    = local.silver_bucket
    "--source_database"                  = aws_glue_catalog_database.bronze_db.name
    "--target_database"                  = aws_glue_catalog_database.silver_db.name
  }

  max_retries       = 0
  timeout           = 120
  glue_version      = "4.0"
  number_of_workers = 2
  worker_type       = "Standard"

  tags = {
    Name        = "sgpj-bronze-to-silver"
    Environment = "data-lake"
    Pipeline    = "bronze-to-silver"
  }
}

# ── Glue ETL Job: Silver → Gold ─────────────────────────────────────────────────
resource "aws_glue_job" "silver_to_gold" {
  count       = var.enable_data_lake_iam ? 1 : 0
  name        = "sgpj-silver-to-gold"
  description = "ETL job to aggregate silver data into gold business metrics"
  role_arn    = aws_iam_role.glue_job_role[0].arn

  command {
    name            = "glueetl"
    script_location = "s3://${local.gold_bucket}/scripts/silver_to_gold.py"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"                     = "python"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-metrics"                   = ""
    "--enable-spark-ui"                  = "true"
    "--spark-event-logs-path"            = "s3://${local.gold_bucket}/logs/spark/"
    "--TempDir"                          = "s3://${local.gold_bucket}/tmp/"
    "--source_bucket"                    = local.silver_bucket
    "--target_bucket"                    = local.gold_bucket
    "--source_database"                  = aws_glue_catalog_database.silver_db.name
    "--target_database"                  = aws_glue_catalog_database.gold_db.name
  }

  max_retries       = 0
  timeout           = 120
  glue_version      = "4.0"
  number_of_workers = 2
  worker_type       = "Standard"

  tags = {
    Name        = "sgpj-silver-to-gold"
    Environment = "data-lake"
    Pipeline    = "silver-to-gold"
  }
}

# ── Outputs ────────────────────────────────────────────────────────────────────
output "bronze_bucket_name" {
  description = "Nome do bucket bronze"
  value       = local.bronze_bucket
}

output "silver_bucket_name" {
  description = "Nome do bucket silver"
  value       = local.silver_bucket
}

output "gold_bucket_name" {
  description = "Nome do bucket gold"
  value       = local.gold_bucket
}

output "bronze_bucket_arn" {
  description = "ARN do bucket bronze"
  value       = local.bronze_bucket_arn
}

output "silver_bucket_arn" {
  description = "ARN do bucket silver"
  value       = local.silver_bucket_arn
}

output "gold_bucket_arn" {
  description = "ARN do bucket gold"
  value       = local.gold_bucket_arn
}

output "glue_crawler_role_arn" {
  description = "ARN do role IAM para Glue Crawlers (null se enable_data_lake_iam=false)"
  value       = var.enable_data_lake_iam ? aws_iam_role.glue_crawler_role[0].arn : null
}

output "bronze_database_name" {
  description = "Nome do database Glue bronze"
  value       = aws_glue_catalog_database.bronze_db.name
}

output "silver_database_name" {
  description = "Nome do database Glue silver"
  value       = aws_glue_catalog_database.silver_db.name
}

output "bronze_crawler_name" {
  description = "Nome do crawler bronze (null se enable_data_lake_iam=false)"
  value       = var.enable_data_lake_iam ? aws_glue_crawler.bronze_crawler[0].name : null
}

output "silver_crawler_name" {
  description = "Nome do crawler silver (null se enable_data_lake_iam=false)"
  value       = var.enable_data_lake_iam ? aws_glue_crawler.silver_crawler[0].name : null
}

output "gold_crawler_name" {
  description = "Nome do crawler gold (null se enable_data_lake_iam=false)"
  value       = var.enable_data_lake_iam ? aws_glue_crawler.gold_crawler[0].name : null
}

output "gold_database_name" {
  description = "Nome do database Glue gold"
  value       = aws_glue_catalog_database.gold_db.name
}

output "glue_job_role_arn" {
  description = "ARN do role IAM para Glue Jobs (null se enable_data_lake_iam=false)"
  value       = var.enable_data_lake_iam ? aws_iam_role.glue_job_role[0].arn : null
}

output "bronze_to_silver_job_name" {
  description = "Nome do job Glue Bronze → Silver (null se enable_data_lake_iam=false)"
  value       = var.enable_data_lake_iam ? aws_glue_job.bronze_to_silver[0].name : null
}

output "silver_to_gold_job_name" {
  description = "Nome do job Glue Silver → Gold (null se enable_data_lake_iam=false)"
  value       = var.enable_data_lake_iam ? aws_glue_job.silver_to_gold[0].name : null
}
