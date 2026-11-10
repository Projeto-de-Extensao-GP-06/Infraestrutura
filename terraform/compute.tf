# ------------------------------------------------------------------------------
# Modulo de Computacao (EC2 Instances + Application Load Balancer)
# Substitui o antigo ec2.tf usando for_each sobre o map de instancias
# ------------------------------------------------------------------------------

module "compute" {
  source = "./modules/compute"

  key_name       = var.Key-All
  ami_id         = var.ami_id
  instance_type  = var.instance_type
  user_data_path = "${path.module}/../scripts/util/bootstrap.sh"

  instances_config = {
    app_a = {
      subnet_id                   = aws_subnet.public_a.id
      vpc_security_group_ids      = [aws_security_group.app.id, aws_security_group.swarm.id]
      iam_instance_profile        = var.enable_observability_iam ? try(aws_iam_instance_profile.observability_ec2_profile[0].name, var.observability_existing_instance_profile_name) : var.observability_existing_instance_profile_name
      associate_public_ip_address = true
      tags = {
        Name = "ec2-app-a"
      }
    }
    app_b = {
      subnet_id                   = aws_subnet.public_b.id
      vpc_security_group_ids      = [aws_security_group.app.id, aws_security_group.swarm.id]
      iam_instance_profile        = var.enable_observability_iam ? try(aws_iam_instance_profile.observability_ec2_profile[0].name, var.observability_existing_instance_profile_name) : var.observability_existing_instance_profile_name
      associate_public_ip_address = true
      tags = {
        Name = "ec2-app-b"
      }
    }
    backend_a = {
      subnet_id                   = aws_subnet.private_backend_a.id
      vpc_security_group_ids      = [aws_security_group.backend.id, aws_security_group.swarm.id]
      instance_type               = var.backend_instance_type
      iam_instance_profile        = var.observability_existing_instance_profile_name
      associate_public_ip_address = false
      tags = {
        Name = "ec2-backend-a"
      }
    }
    backend_b = {
      subnet_id                   = aws_subnet.private_backend_b.id
      vpc_security_group_ids      = [aws_security_group.backend.id, aws_security_group.swarm.id]
      instance_type               = var.backend_instance_type
      iam_instance_profile        = var.observability_existing_instance_profile_name
      associate_public_ip_address = false
      tags = {
        Name = "ec2-backend-b"
      }
    }
    db = {
      subnet_id                   = aws_subnet.private_db_a.id
      vpc_security_group_ids      = [aws_security_group.db.id]
      iam_instance_profile        = var.observability_existing_instance_profile_name
      associate_public_ip_address = false
      tags = {
        Name = "ec2-db"
      }
    }
  }

  # Configuracao condicional de observabilidade
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

# -- Blocos de migracao de State (Zero Downtime / Zero Destroy) ----------------
moved {
  from = aws_instance.app_a
  to   = module.compute.aws_instance.instances["app_a"]
}

moved {
  from = aws_instance.app_b
  to   = module.compute.aws_instance.instances["app_b"]
}

moved {
  from = aws_instance.backend_a
  to   = module.compute.aws_instance.instances["backend_a"]
}

moved {
  from = aws_instance.backend_b
  to   = module.compute.aws_instance.instances["backend_b"]
}

moved {
  from = aws_instance.db
  to   = module.compute.aws_instance.instances["db"]
}

moved {
  from = aws_instance.observability[0]
  to   = module.compute.aws_instance.observability[0]
}

moved {
  from = aws_lb.app
  to   = module.compute.aws_lb.app
}

moved {
  from = aws_lb_target_group.app
  to   = module.compute.aws_lb_target_group.app
}

moved {
  from = aws_lb_listener.http
  to   = module.compute.aws_lb_listener.http
}

moved {
  from = aws_lb_target_group_attachment.app_a
  to   = module.compute.aws_lb_target_group_attachment.app["app_a"]
}

moved {
  from = aws_lb_target_group_attachment.app_b
  to   = module.compute.aws_lb_target_group_attachment.app["app_b"]
}
