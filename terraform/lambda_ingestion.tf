# ──────────────────────────────────────────────────────────────────────────────
# Pipeline de Ingestão de Dados Externos via AWS Lambda (SGPJ Data Lake)
# Origem: S3 sgpj-external -> Evento S3 -> Lambda -> S3 sgpj-bronze (raw_data/)
# Compatível com AWS Academy (LabRole) e LocalStack
# ──────────────────────────────────────────────────────────────────────────────

variable "enable_lambda_ingestion" {
  description = "Habilita a função Lambda de ingestão e a notificação de eventos S3"
  type        = bool
  default     = true
}

variable "use_existing_lab_role" {
  description = "No AWS Academy, usa LabRole pré-existente para evitar bloqueio por SCP de iam:CreateRole"
  type        = bool
  default     = true
}

# ── IAM Role para a função Lambda ─────────────────────────────────────────────
data "aws_iam_policy_document" "lambda_assume_role" {
  count = var.enable_lambda_ingestion && !var.use_existing_lab_role ? 1 : 0

  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "lambda_ingestion_role" {
  count              = var.enable_lambda_ingestion && !var.use_existing_lab_role ? 1 : 0
  name               = "sgpj-lambda-ingestion-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role[0].json

  tags = {
    Name        = "sgpj-lambda-ingestion-role"
    Environment = "data-lake"
  }
}

data "aws_iam_policy_document" "lambda_ingestion_policy" {
  count = var.enable_lambda_ingestion && !var.use_existing_lab_role ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:CopyObject"
    ]
    resources = [
      local.external_bucket_arn,
      "${local.external_bucket_arn}/*",
      local.bronze_bucket_arn,
      "${local.bronze_bucket_arn}/*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "lambda_ingestion_policy" {
  count  = var.enable_lambda_ingestion && !var.use_existing_lab_role ? 1 : 0
  name   = "sgpj-lambda-ingestion-policy"
  role   = aws_iam_role.lambda_ingestion_role[0].id
  policy = data.aws_iam_policy_document.lambda_ingestion_policy[0].json
}

locals {
  lambda_role_arn = var.use_existing_lab_role ? "arn:aws:iam::${local.account_id}:role/LabRole" : try(aws_iam_role.lambda_ingestion_role[0].arn, "")
}

# ── Empacotamento do Código Python (ZIP) ───────────────────────────────────────
data "archive_file" "lambda_zip" {
  count       = var.enable_lambda_ingestion ? 1 : 0
  type        = "zip"
  source_file = "${path.module}/scripts/lambda_ingestion.py"
  output_path = "${path.module}/scripts/lambda_ingestion.zip"
}

# ── CloudWatch Log Group para o Lambda ─────────────────────────────────────────
resource "aws_cloudwatch_log_group" "lambda_ingestion" {
  count             = var.enable_lambda_ingestion ? 1 : 0
  name              = "/aws/lambda/sgpj-data-ingestion"
  retention_in_days = 7

  tags = {
    Name        = "sgpj-log-group-data-ingestion"
    Environment = "data-lake"
  }
}

# ── Função Lambda de Ingestão ──────────────────────────────────────────────────
resource "aws_lambda_function" "data_ingestion" {
  count            = var.enable_lambda_ingestion ? 1 : 0
  function_name    = "sgpj-data-ingestion"
  description      = "Lambda para ingestao e particionamento de dados externos para camada Bronze"
  role             = local.lambda_role_arn
  handler          = "lambda_ingestion.lambda_handler"
  runtime          = "python3.11"
  filename         = data.archive_file.lambda_zip[0].output_path
  source_code_hash = data.archive_file.lambda_zip[0].output_base64sha256

  environment {
    variables = {
      SOURCE_BUCKET = local.external_bucket
      TARGET_BUCKET = local.bronze_bucket
    }
  }

  timeout     = 60
  memory_size = 256

  tags = {
    Name        = "sgpj-data-ingestion"
    Environment = "data-lake"
    Purpose     = "external-ingestion"
  }
}

# ── Permissão para o S3 invocar a Função Lambda ────────────────────────────────
resource "aws_lambda_permission" "allow_bucket" {
  count         = var.enable_lambda_ingestion ? 1 : 0
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.data_ingestion[0].function_name
  principal     = "s3.amazonaws.com"
  source_arn    = local.external_bucket_arn
}

# ── Notificação de Evento no Bucket S3 (S3 -> Lambda) ─────────────────────────
resource "aws_s3_bucket_notification" "external_notification" {
  count  = var.enable_lambda_ingestion ? 1 : 0
  bucket = local.external_bucket

  lambda_function {
    lambda_function_arn = aws_lambda_function.data_ingestion[0].arn
    events              = ["s3:ObjectCreated:*"]
    filter_suffix       = ".json"
  }

  depends_on = [
    null_resource.s3_data_lake,
    aws_lambda_permission.allow_bucket
  ]
}
