# ------------------------------------------------------------------------------
# Pipeline de Ingestao de Dados Externos via AWS Lambda (SGPJ Data Lake)
# Fontes Externas (Ref: XAKCN/EDA_Brasil): BACEN SGS, IBGE SIDRA e BACEN Olinda
# Gatilhos: EventBridge (Agendado) / Invocacao Manual
# Destino: S3 sgpj-bronze (raw_data/{fonte}/{dataset}/year=YYYY/month=MM/day=DD/)
# Compativel com AWS Academy (LabRole) e LocalStack
# ------------------------------------------------------------------------------

variable "enable_lambda_ingestion" {
  description = "Habilita a funcao Lambda de ingestao, agendamento EventBridge e notificacao de eventos S3"
  type        = bool
  default     = true
}

variable "lambda_ingestion_schedule" {
  description = "Expressao cron/rate do EventBridge para coleta periodica das APIs externas (BACEN/IBGE)"
  type        = string
  default     = "cron(0 6 * * ? *)"
}

variable "use_existing_lab_role" {
  description = "No AWS Academy, usa LabRole pre-existente para evitar bloqueio por SCP de iam:CreateRole"
  type        = bool
  default     = true
}

# -- IAM Role para a funcao Lambda ---------------------------------------------
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

# -- Empacotamento do Codigo Python (ZIP) ---------------------------------------
data "archive_file" "lambda_zip" {
  count       = var.enable_lambda_ingestion ? 1 : 0
  type        = "zip"
  source_file = "${path.module}/scripts/lambda_ingestion.py"
  output_path = "${path.module}/scripts/lambda_ingestion.zip"
}

# -- CloudWatch Log Group para o Lambda -----------------------------------------
resource "aws_cloudwatch_log_group" "lambda_ingestion" {
  count             = var.enable_lambda_ingestion ? 1 : 0
  name              = "/aws/lambda/sgpj-data-ingestion"
  retention_in_days = 7

  tags = {
    Name        = "sgpj-log-group-data-ingestion"
    Environment = "data-lake"
  }
}

# -- Funcao Lambda de Ingestao --------------------------------------------------
resource "aws_lambda_function" "data_ingestion" {
  count            = var.enable_lambda_ingestion ? 1 : 0
  function_name    = "sgpj-data-ingestion"
  description      = "Lambda para ingestao de bases externas (BACEN SGS, IBGE SIDRA, BACEN Olinda - ref EDA_Brasil) para camada Bronze"
  role             = local.lambda_role_arn
  handler          = "lambda_ingestion.lambda_handler"
  runtime          = "python3.11"
  filename         = data.archive_file.lambda_zip[0].output_path
  source_code_hash = data.archive_file.lambda_zip[0].output_base64sha256

  environment {
    variables = {
      TARGET_BUCKET = local.bronze_bucket
      START_DATE_BR = "01/01/2015"
      OLINDA_TOP    = "50000"
    }
  }

  timeout     = 300
  memory_size = 512

  tags = {
    Name        = "sgpj-data-ingestion"
    Environment = "data-lake"
    Purpose     = "external-ingestion"
  }
}

# -- Agendamento EventBridge (Coleta Ativa das APIs BACEN / IBGE) ---------------
resource "aws_cloudwatch_event_rule" "lambda_ingestion_schedule" {
  count               = var.enable_lambda_ingestion ? 1 : 0
  name                = "sgpj-data-ingestion-schedule"
  description         = "Dispara periodicamente a Lambda de ingestao de dados externos (BACEN SGS, IBGE SIDRA, BACEN Olinda)"
  schedule_expression = var.lambda_ingestion_schedule

  tags = {
    Name        = "sgpj-data-ingestion-schedule"
    Environment = "data-lake"
  }
}

resource "aws_cloudwatch_event_target" "lambda_ingestion_target" {
  count     = var.enable_lambda_ingestion ? 1 : 0
  rule      = aws_cloudwatch_event_rule.lambda_ingestion_schedule[0].name
  target_id = "sgpj-data-ingestion-lambda"
  arn       = aws_lambda_function.data_ingestion[0].arn
}

resource "aws_lambda_permission" "allow_eventbridge" {
  count         = var.enable_lambda_ingestion ? 1 : 0
  statement_id  = "AllowExecutionFromEventBridge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.data_ingestion[0].function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.lambda_ingestion_schedule[0].arn
}

# -- Permissao para o S3 invocar a Funcao Lambda --------------------------------
