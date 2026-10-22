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

# ── Sincronização Automática: Docker Hub -> Amazon ECR ─────────────────────────
resource "null_resource" "sync_dockerhub_to_ecr" {
  count = var.auto_sync_ecr ? 1 : 0

  triggers = {
    frontend_ecr = aws_ecr_repository.frontend.repository_url
    backend_ecr  = aws_ecr_repository.backend.repository_url
    frontend_hub = var.docker_frontend_hub_image
    backend_hub  = var.docker_backend_hub_image
    always_run   = timestamp()
  }

  depends_on = [
    aws_ecr_repository.frontend,
    aws_ecr_repository.backend
  ]

  provisioner "local-exec" {
    command = "wsl -e bash -c \"chmod +x ../scripts/sync_dockerhub_to_ecr.sh && ../scripts/sync_dockerhub_to_ecr.sh ${var.region} ${aws_ecr_repository.frontend.repository_url} ${aws_ecr_repository.backend.repository_url} ${var.docker_frontend_hub_image} ${var.docker_backend_hub_image}\""
  }
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
