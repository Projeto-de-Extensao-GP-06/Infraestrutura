# ── Bucket S3 para dados externos (staging) ─────────────────────────────────────
resource "aws_s3_bucket" "external" {
  bucket = "sgpj-external"

  tags = {
    Name        = "sgpj-external"
    Environment = "data-lake"
    Purpose     = "external-ingestion"
  }
}

resource "aws_s3_bucket_versioning" "external" {
  bucket = aws_s3_bucket.external.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "external" {
  bucket = aws_s3_bucket.external.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ── IAM Role para Lambda de ingestão ─────────────────────────────────────────────
data "aws_iam_policy_document" "lambda_assume_role" {
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
  name               = "sgpj-lambda-ingestion-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
  tags               = { Name = "sgpj-lambda-ingestion-role" }
}

data "aws_iam_policy_document" "lambda_ingestion_policy" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:CopyObject"
    ]
    resources = [
      aws_s3_bucket.external.arn,
      "${aws_s3_bucket.external.arn}/*",
      aws_s3_bucket.bronze.arn,
      "${aws_s3_bucket.bronze.arn}/*"
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
  name   = "sgpj-lambda-ingestion-policy"
  role   = aws_iam_role.lambda_ingestion_role.id
  policy = data.aws_iam_policy_document.lambda_ingestion_policy.json
}

# ── CloudWatch Log Group para Lambda ────────────────────────────────────────────
resource "aws_cloudwatch_log_group" "lambda_ingestion" {
  name              = "/aws/lambda/sgpj-data-ingestion"
  retention_in_days = 7
}

# ── Lambda Function para ingestão de dados ─────────────────────────────────────
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/scripts/lambda_ingestion.py"
  output_path = "${path.module}/scripts/lambda_ingestion.zip"
}

resource "aws_lambda_function" "data_ingestion" {
  function_name    = "sgpj-data-ingestion"
  description      = "Lambda para ingestão de dados externos para camada bronze"
  role             = aws_iam_role.lambda_ingestion_role.arn
  handler          = "lambda_ingestion.lambda_handler"
  runtime          = "python3.11"
  filename         = data.archive_file.lambda_zip.output_path
  source_code_hash = data.archive_file.lambda_zip.output_base64sha256

  environment {
    variables = {
      SOURCE_BUCKET = aws_s3_bucket.external.bucket
      TARGET_BUCKET = aws_s3_bucket.bronze.bucket
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

# ── S3 Event Notification para acionar Lambda ─────────────────────────────────
resource "aws_s3_bucket_notification" "external_notification" {
  bucket = aws_s3_bucket.external.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.data_ingestion.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = ""
    filter_suffix       = ".json"
  }

  depends_on = [aws_lambda_permission.allow_bucket]
}

# ── Permissão para S3 invocar Lambda ───────────────────────────────────────────
resource "aws_lambda_permission" "allow_bucket" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.data_ingestion.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.external.arn
}
