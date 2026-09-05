# ── Data Lake S3 Buckets (Bronze, Silver, Gold) ────────────────────────────────
resource "aws_s3_bucket" "bronze" {
  bucket = "sgpj-bronze"

  tags = {
    Name        = "sgpj-bronze"
    Environment = "data-lake"
    Layer       = "bronze"
  }
}

resource "aws_s3_bucket_versioning" "bronze" {
  bucket = aws_s3_bucket.bronze.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "bronze" {
  bucket = aws_s3_bucket.bronze.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket" "silver" {
  bucket = "sgpj-silver"

  tags = {
    Name        = "sgpj-silver"
    Environment = "data-lake"
    Layer       = "silver"
  }
}

resource "aws_s3_bucket_versioning" "silver" {
  bucket = aws_s3_bucket.silver.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "silver" {
  bucket = aws_s3_bucket.silver.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket" "gold" {
  bucket = "sgpj-gold"

  tags = {
    Name        = "sgpj-gold"
    Environment = "data-lake"
    Layer       = "gold"
  }
}

resource "aws_s3_bucket_versioning" "gold" {
  bucket = aws_s3_bucket.gold.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "gold" {
  bucket = aws_s3_bucket.gold.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ── IAM Role for Glue Crawlers ─────────────────────────────────────────────────
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
    resources = [
      aws_s3_bucket.bronze.arn,
      "${aws_s3_bucket.bronze.arn}/*",
      aws_s3_bucket.silver.arn,
      "${aws_s3_bucket.silver.arn}/*",
      aws_s3_bucket.gold.arn,
      "${aws_s3_bucket.gold.arn}/*"
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
  name   = "sgpj-glue-crawler-policy"
  role   = aws_iam_role.glue_crawler_role.id
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

data "aws_caller_identity" "current" {}

# ── Glue Crawlers ──────────────────────────────────────────────────────────────
resource "aws_glue_crawler" "bronze_crawler" {
  name          = "sgpj-bronze-crawler"
  role          = aws_iam_role.glue_crawler_role.arn
  database_name = aws_glue_catalog_database.bronze_db.name
  description   = "Crawler for bronze layer raw data"

  s3_target {
    path = "s3://${aws_s3_bucket.bronze.bucket}/"
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
  role          = aws_iam_role.glue_crawler_role.arn
  database_name = aws_glue_catalog_database.silver_db.name
  description   = "Crawler for silver layer cleaned data"

  s3_target {
    path = "s3://${aws_s3_bucket.silver.bucket}/"
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
  role          = aws_iam_role.glue_crawler_role.arn
  database_name = aws_glue_catalog_database.gold_db.name
  description   = "Crawler for gold layer aggregated data"

  s3_target {
    path = "s3://${aws_s3_bucket.gold.bucket}/"
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
      aws_s3_bucket.bronze.arn,
      "${aws_s3_bucket.bronze.arn}/*",
      aws_s3_bucket.silver.arn,
      "${aws_s3_bucket.silver.arn}/*",
      aws_s3_bucket.gold.arn,
      "${aws_s3_bucket.gold.arn}/*"
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
  name   = "sgpj-glue-job-policy"
  role   = aws_iam_role.glue_job_role.id
  policy = data.aws_iam_policy_document.glue_job_policy.json
}

# ── Glue ETL Job: Bronze → Silver ───────────────────────────────────────────────
resource "aws_glue_job" "bronze_to_silver" {
  name        = "sgpj-bronze-to-silver"
  description = "ETL job to transform bronze raw data to silver curated format"
  role_arn    = aws_iam_role.glue_job_role.arn

  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.silver.bucket}/scripts/bronze_to_silver.py"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"           = "python"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-metrics"         = ""
    "--enable-spark-ui"        = "true"
    "--spark-event-logs-path"  = "s3://${aws_s3_bucket.silver.bucket}/logs/spark/"
    "--TempDir"                = "s3://${aws_s3_bucket.silver.bucket}/tmp/"
    "--source_bucket"          = aws_s3_bucket.bronze.bucket
    "--target_bucket"          = aws_s3_bucket.silver.bucket
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
  role_arn    = aws_iam_role.glue_job_role.arn

  command {
    name            = "glueetl"
    script_location = "s3://${aws_s3_bucket.gold.bucket}/scripts/silver_to_gold.py"
    python_version  = "3"
  }

  default_arguments = {
    "--job-language"           = "python"
    "--enable-continuous-cloudwatch-log" = "true"
    "--enable-metrics"         = ""
    "--enable-spark-ui"        = "true"
    "--spark-event-logs-path"  = "s3://${aws_s3_bucket.gold.bucket}/logs/spark/"
    "--TempDir"                = "s3://${aws_s3_bucket.gold.bucket}/tmp/"
    "--source_bucket"          = aws_s3_bucket.silver.bucket
    "--target_bucket"          = aws_s3_bucket.gold.bucket
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
  value       = aws_s3_bucket.bronze.bucket
}

output "silver_bucket_name" {
  description = "Nome do bucket silver"
  value       = aws_s3_bucket.silver.bucket
}

output "gold_bucket_name" {
  description = "Nome do bucket gold"
  value       = aws_s3_bucket.gold.bucket
}

output "bronze_bucket_arn" {
  description = "ARN do bucket bronze"
  value       = aws_s3_bucket.bronze.arn
}

output "silver_bucket_arn" {
  description = "ARN do bucket silver"
  value       = aws_s3_bucket.silver.arn
}

output "gold_bucket_arn" {
  description = "ARN do bucket gold"
  value       = aws_s3_bucket.gold.arn
}

output "glue_crawler_role_arn" {
  description = "ARN do role IAM para Glue Crawlers"
  value       = aws_iam_role.glue_crawler_role.arn
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
  value       = aws_iam_role.glue_job_role.arn
}

output "bronze_to_silver_job_name" {
  description = "Nome do job Glue Bronze → Silver"
  value       = aws_glue_job.bronze_to_silver.name
}

output "silver_to_gold_job_name" {
  description = "Nome do job Glue Silver → Gold"
  value       = aws_glue_job.silver_to_gold.name
}