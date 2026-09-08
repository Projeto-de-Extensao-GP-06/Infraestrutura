# ── Data Lake S3 Buckets (Bronze, Silver, Gold) ────────────────────────────────
# Using data sources for existing buckets to avoid object lock permission issues
data "aws_s3_bucket" "bronze" {
  bucket = "sgpj-bronze"
}

resource "aws_s3_bucket_versioning" "bronze" {
  bucket = data.aws_s3_bucket.bronze.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "bronze" {
  bucket = data.aws_s3_bucket.bronze.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "aws_s3_bucket" "silver" {
  bucket = "sgpj-silver"
}

resource "aws_s3_bucket_versioning" "silver" {
  bucket = data.aws_s3_bucket.silver.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "silver" {
  bucket = data.aws_s3_bucket.silver.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

data "aws_s3_bucket" "gold" {
  bucket = "sgpj-gold"
}

resource "aws_s3_bucket_versioning" "gold" {
  bucket = data.aws_s3_bucket.gold.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "gold" {
  bucket = data.aws_s3_bucket.gold.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ── IAM Role for Glue Crawlers ─────────────────────────────────────────────────
# Using existing LabRole instead of creating new IAM role due to permission constraints
data "aws_iam_role" "glue_crawler_role" {
  name = "LabRole"
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

data "aws_caller_identity" "current" {}

# ── Glue Crawlers ──────────────────────────────────────────────────────────────
resource "aws_glue_crawler" "bronze_crawler" {
  name          = "sgpj-bronze-crawler"
  role          = data.aws_iam_role.glue_crawler_role.arn
  database_name = aws_glue_catalog_database.bronze_db.name
  description   = "Crawler for bronze layer raw data"

  s3_target {
    path = "s3://${data.aws_s3_bucket.bronze.bucket}/"
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
  name          = "sgpj-silver-crawler"
  role          = data.aws_iam_role.glue_crawler_role.arn
  database_name = aws_glue_catalog_database.silver_db.name
  description   = "Crawler for silver layer cleaned data"

  s3_target {
    path = "s3://${data.aws_s3_bucket.silver.bucket}/"
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
  name          = "sgpj-gold-crawler"
  role          = data.aws_iam_role.glue_crawler_role.arn
  database_name = aws_glue_catalog_database.gold_db.name
  description   = "Crawler for gold layer aggregated data"

  s3_target {
    path = "s3://${data.aws_s3_bucket.gold.bucket}/"
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
# Using existing LabRole instead of creating new IAM role due to permission constraints
data "aws_iam_role" "glue_job_role" {
  name = "LabRole"
}

# ── Glue ETL Job: Bronze → Silver ───────────────────────────────────────────────
resource "aws_glue_job" "bronze_to_silver" {
  name        = "sgpj-bronze-to-silver"
  description = "ETL job to transform bronze raw data to silver curated format"
  role_arn    = data.aws_iam_role.glue_job_role.arn

  command {
    name            = "glueetl"
    script_location = "s3://${data.aws_s3_bucket.silver.bucket}/scripts/bronze_to_silver.py"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"           = "python"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-metrics"         = ""
    "--enable-spark-ui"        = "true"
    "--spark-event-logs-path"  = "s3://${data.aws_s3_bucket.silver.bucket}/logs/spark/"
    "--TempDir"                = "s3://${data.aws_s3_bucket.silver.bucket}/tmp/"
    "--source_bucket"          = data.aws_s3_bucket.bronze.bucket
    "--target_bucket"          = data.aws_s3_bucket.silver.bucket
    "--source_database"        = aws_glue_catalog_database.bronze_db.name
    "--target_database"        = aws_glue_catalog_database.silver_db.name
  }

  max_retries    = 0
  timeout        = 120
  glue_version   = "4.0"
  number_of_workers = 2
  worker_type    = "Standard"

  tags = {
    Name        = "sgpj-bronze-to-silver"
    Environment = "data-lake"
    Pipeline    = "bronze-to-silver"
  }
}

# ── Glue ETL Job: Silver → Gold ─────────────────────────────────────────────────
resource "aws_glue_job" "silver_to_gold" {
  name        = "sgpj-silver-to-gold"
  description = "ETL job to aggregate silver data into gold business metrics"
  role_arn    = data.aws_iam_role.glue_job_role.arn

  command {
    name            = "glueetl"
    script_location = "s3://${data.aws_s3_bucket.gold.bucket}/scripts/silver_to_gold.py"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"           = "python"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-metrics"         = ""
    "--enable-spark-ui"        = "true"
    "--spark-event-logs-path"  = "s3://${data.aws_s3_bucket.gold.bucket}/logs/spark/"
    "--TempDir"                = "s3://${data.aws_s3_bucket.gold.bucket}/tmp/"
    "--source_bucket"          = data.aws_s3_bucket.silver.bucket
    "--target_bucket"          = data.aws_s3_bucket.gold.bucket
    "--source_database"        = aws_glue_catalog_database.silver_db.name
    "--target_database"        = aws_glue_catalog_database.gold_db.name
  }

  max_retries    = 0
  timeout        = 120
  glue_version   = "4.0"
  number_of_workers = 2
  worker_type    = "Standard"

  tags = {
    Name        = "sgpj-silver-to-gold"
    Environment = "data-lake"
    Pipeline    = "silver-to-gold"
  }
}



# ── Outputs ────────────────────────────────────────────────────────────────────
output "bronze_bucket_name" {
  description = "Nome do bucket bronze"
  value       = data.aws_s3_bucket.bronze.bucket
}

output "silver_bucket_name" {
  description = "Nome do bucket silver"
  value       = data.aws_s3_bucket.silver.bucket
}

output "gold_bucket_name" {
  description = "Nome do bucket gold"
  value       = data.aws_s3_bucket.gold.bucket
}

output "bronze_bucket_arn" {
  description = "ARN do bucket bronze"
  value       = data.aws_s3_bucket.bronze.arn
}

output "silver_bucket_arn" {
  description = "ARN do bucket silver"
  value       = data.aws_s3_bucket.silver.arn
}

output "gold_bucket_arn" {
  description = "ARN do bucket gold"
  value       = data.aws_s3_bucket.gold.arn
}

output "glue_crawler_role_arn" {
  description = "ARN do role IAM para Glue Crawlers"
  value       = data.aws_iam_role.glue_crawler_role.arn
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
  description = "Nome do crawler bronze"
  value       = aws_glue_crawler.bronze_crawler.name
}

output "silver_crawler_name" {
  description = "Nome do crawler silver"
  value       = aws_glue_crawler.silver_crawler.name
}

output "gold_crawler_name" {
  description = "Nome do crawler gold"
  value       = aws_glue_crawler.gold_crawler.name
}

output "gold_database_name" {
  description = "Nome do database Glue gold"
  value       = aws_glue_catalog_database.gold_db.name
}

output "glue_job_role_arn" {
  description = "ARN do role IAM para Glue Jobs"
  value       = data.aws_iam_role.glue_job_role.arn
}

output "bronze_to_silver_job_name" {
  description = "Nome do job Glue Bronze → Silver"
  value       = aws_glue_job.bronze_to_silver.name
}

output "silver_to_gold_job_name" {
  description = "Nome do job Glue Silver → Gold"
  value       = aws_glue_job.silver_to_gold.name
}