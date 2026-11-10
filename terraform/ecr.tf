# ------------------------------------------------------------------------------
# AWS ECR -- Elastic Container Registry para Frontend e Backend
# ------------------------------------------------------------------------------

resource "aws_ecr_repository" "frontend" {
  name                 = "sgpj-frontend"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  # Protege o repositorio de ser destruido acidentalmente pelo terraform destroy
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name        = "sgpj-frontend"
    Environment = "production"
  }
}

resource "aws_ecr_repository" "backend" {
  name                 = "sgpj-backend"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  # Protege o repositorio de ser destruido acidentalmente pelo terraform destroy
  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name        = "sgpj-backend"
    Environment = "production"
  }
}

# -- Lifecycle Policy (Expira imagens antigas para economizar espaco e custo) --
resource "aws_ecr_lifecycle_policy" "frontend" {
  repository = aws_ecr_repository.frontend.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Manter apenas as ultimas 10 imagens"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

resource "aws_ecr_lifecycle_policy" "backend" {
  repository = aws_ecr_repository.backend.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Manter apenas as ultimas 10 imagens"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# -- Outputs com as URLs dos Repositorios ---------------------------------------
output "ecr_frontend_repository_url" {
  description = "URL do repositorio ECR para imagem do Frontend"
  value       = aws_ecr_repository.frontend.repository_url
}

output "ecr_backend_repository_url" {
  description = "URL do repositorio ECR para imagem do Backend"
  value       = aws_ecr_repository.backend.repository_url
}

resource "aws_ecr_repository" "agent" {
  name                 = "sgpj-agent"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  lifecycle {
    prevent_destroy = true
  }

  tags = {
    Name        = "sgpj-agent"
    Environment = "production"
  }
}

resource "aws_ecr_lifecycle_policy" "agent" {
  repository = aws_ecr_repository.agent.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Manter apenas as ultimas 10 imagens"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# -- Sincronizacao automatica de Secrets e Build das Imagens via CI/CD --------
resource "null_resource" "sync_github_secrets_and_build" {
  depends_on = [
    aws_ecr_repository.frontend,
    aws_ecr_repository.backend,
    aws_ecr_repository.agent
  ]

  triggers = {
    always_run = timestamp()
  }

  provisioner "local-exec" {
    command     = "powershell.exe -ExecutionPolicy Bypass -File ${path.module}/../scripts/sync-aws-secrets.ps1"
    working_dir = path.module
  }
}