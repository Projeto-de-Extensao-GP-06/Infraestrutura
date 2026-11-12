# -- Bucket de backups do banco de dados ----------------------------------------
# Nome logico: database_backup. S3 nao aceita "_" em nomes, entao usamos hifen
# e account_id para unicidade global.
# Criado via AWS CLI (null_resource) pelo mesmo motivo do data lake (SCP do AWS Academy
# bloqueia GetObjectLockConfiguration no refresh do provider aws_s3_bucket).

locals {
  database_backup_bucket     = "database-backup-${local.account_id}"
  database_backup_bucket_arn = "arn:aws:s3:::${local.database_backup_bucket}"
}

resource "null_resource" "s3_database_backup" {
  triggers = {
    bucket = local.database_backup_bucket
  }

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-Command"]
    command     = <<-EOT
      $ErrorActionPreference = 'Continue'
      if (Test-Path variable:PSNativeCommandUseErrorActionPreference) {
        $PSNativeCommandUseErrorActionPreference = $false
      }
      $region = 'us-east-1'
      $bucket = '${local.database_backup_bucket}'

      $encFile = [System.IO.Path]::GetTempFileName()
      Set-Content -Path $encFile -Value '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"},"BucketKeyEnabled":false}]}'
      $encFilePath = $encFile.Replace('\', '/')

      $pabFile = [System.IO.Path]::GetTempFileName()
      Set-Content -Path $pabFile -Value '{"BlockPublicAcls":true,"IgnorePublicAcls":true,"BlockPublicPolicy":true,"RestrictPublicBuckets":true}'
      $pabFilePath = $pabFile.Replace('\', '/')

      try {
        Write-Host ">>> Configurando bucket: $bucket"

        $null = & cmd /c "aws s3api head-bucket --bucket $bucket 2>nul"
        if ($LASTEXITCODE -ne 0) {
          Write-Host "Criando bucket $bucket..."
          aws s3api create-bucket --bucket $bucket --region $region
          if ($LASTEXITCODE -ne 0) { throw "Falha ao criar bucket $bucket" }
        } else {
          Write-Host "Bucket $bucket ja existe, pulando criacao."
        }

        aws s3api put-bucket-versioning --bucket $bucket --versioning-configuration Status=Enabled
        if ($LASTEXITCODE -ne 0) { throw "Falha no versionamento de $bucket" }

        aws s3api put-bucket-encryption --bucket $bucket --server-side-encryption-configuration "file://$encFilePath"
        if ($LASTEXITCODE -ne 0) { throw "Falha na criptografia de $bucket" }

        aws s3api put-public-access-block --bucket $bucket --public-access-block-configuration "file://$pabFilePath"
        if ($LASTEXITCODE -ne 0) { throw "Falha no public access block de $bucket" }

        Write-Host ">>> Bucket $bucket OK"
      } finally {
        if (Test-Path $encFile) { Remove-Item $encFile -Force }
        if (Test-Path $pabFile) { Remove-Item $pabFile -Force }
      }
    EOT
  }
}

# -- Notificacao por e-mail (SNS) do resultado do backup --------------------------
variable "backup_notification_email" {
  description = "E-mail que recebe o resultado (sucesso/falha) do backup do banco"
  default     = "coffe2765@gmail.com"
}

resource "aws_sns_topic" "database_backup" {
  name = "sgpj-database-backup"
}

resource "aws_sns_topic_subscription" "database_backup_email" {
  topic_arn = aws_sns_topic.database_backup.arn
  protocol  = "email"
  endpoint  = var.backup_notification_email
}

output "database_backup_sns_topic_arn" {
  description = "ARN do topico SNS de notificacao do backup"
  value       = aws_sns_topic.database_backup.arn
}

output "database_backup_bucket_name" {
  description = "Nome do bucket de backups do banco de dados"
  value       = local.database_backup_bucket
}

output "database_backup_bucket_arn" {
  description = "ARN do bucket de backups do banco de dados"
  value       = local.database_backup_bucket_arn
}
