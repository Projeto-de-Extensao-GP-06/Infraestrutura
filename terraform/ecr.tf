# ──────────────────────────────────────────────────────────────────────────────
# AWS ECR — Elastic Container Registry para Frontend e Backend
# ──────────────────────────────────────────────────────────────────────────────

resource "aws_ecr_repository" "frontend" {
  name                 = "sgpj-frontend"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
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

  tags = {
    Name        = "sgpj-backend"
    Environment = "production"
  }
}

# ── Lifecycle Policy (Expira imagens antigas para economizar espaço e custo) ──
resource "aws_ecr_lifecycle_policy" "frontend" {
  repository = aws_ecr_repository.frontend.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Manter apenas as ultimas 10 imagens"
        selection = {
          tagStatus     = "any"
          countType     = "imageCountMoreThan"
          countNumber   = 10
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
          tagStatus     = "any"
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}

# ── Outputs com as URLs dos Repositórios ───────────────────────────────────────
output "ecr_frontend_repository_url" {
  description = "URL do repositorio ECR para imagem do Frontend"
  value       = aws_ecr_repository.frontend.repository_url
}

output "ecr_backend_repository_url" {
  description = "URL do repositorio ECR para imagem do Backend"
  value       = aws_ecr_repository.backend.repository_url
}
