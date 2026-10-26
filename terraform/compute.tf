# ──────────────────────────────────────────────────────────────────────────────
# Módulo de Computação (EC2 Instances + Application Load Balancer)
# Substitui o antigo ec2.tf usando for_each sobre o map de instâncias
# ──────────────────────────────────────────────────────────────────────────────

module "compute" {
  source = "./modules/compute"

  key_name       = var.Key-All
  ami_id         = var.ami_id
  instance_type  = var.instance_type
  user_data_path = "${path.module}/../scripts/util/bootstrap.sh"

  instances_config = {
    app_a = {
      subnet_id                   = aws_subnet.public_a.id
      vpc_security_group_ids      = [aws_security_group.app.id]
      iam_instance_profile        = var.enable_observability_iam ? try(aws_iam_instance_profile.observability_ec2_profile[0].name, var.observability_existing_instance_profile_name) : var.observability_existing_instance_profile_name
      associate_public_ip_address = true
      tags = {
        Name = "ec2-app-a"
      }
    }
    app_b = {
      subnet_id                   = aws_subnet.public_b.id
      vpc_security_group_ids      = [aws_security_group.app.id]
      iam_instance_profile        = var.enable_observability_iam ? try(aws_iam_instance_profile.observability_ec2_profile[0].name, var.observability_existing_instance_profile_name) : var.observability_existing_instance_profile_name
      associate_public_ip_address = true
      tags = {
        Name = "ec2-app-b"
      }
    }
    backend_a = {
      subnet_id                   = aws_subnet.private_backend_a.id
      vpc_security_group_ids      = [aws_security_group.backend.id]
      iam_instance_profile        = var.observability_existing_instance_profile_name
      associate_public_ip_address = false
      tags = {
        Name = "ec2-backend-a"
      }
    }
    backend_b = {
      subnet_id                   = aws_subnet.private_backend_b.id
      vpc_security_group_ids      = [aws_security_group.backend.id]
      iam_instance_profile        = var.observability_existing_instance_profile_name
      associate_public_ip_address = false
      tags = {
        Name = "ec2-backend-b"
      }
    }
    db = {
      subnet_id                   = aws_subnet.private_db_a.id
      vpc_security_group_ids      = [aws_security_group.db.id]
      iam_instance_profile        = null
      associate_public_ip_address = false
      tags = {
        Name = "ec2-db"
      }
    }
  }

  # Configuração condicional de observabilidade
  enable_observability = var.enable_observability
  observability_config = var.enable_observability ? {
    subnet_id              = aws_subnet.public_obs[0].id
    vpc_security_group_ids = [aws_security_group.observability[0].id]
    iam_instance_profile   = try(aws_iam_instance_profile.observability_ec2_profile[0].name, var.observability_existing_instance_profile_name)
    tags = {
      Name        = "ec2-observability"
      Environment = "production"
      Role        = "observability"
    }
  } : null

  # Application Load Balancer
  alb_security_group_id = aws_security_group.alb.id
  alb_subnet_ids        = [aws_subnet.public_a.id, aws_subnet.public_b.id]
  vpc_id                = aws_vpc.sgpj_vpc.id
  target_instances      = ["app_a", "app_b"]
}
