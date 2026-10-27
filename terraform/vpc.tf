# ── VPC ────────────────────────────────────────────────────────────────────
resource "aws_vpc" "sgpj_vpc" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "sgpj-vpc" }
}

# ── Internet Gateway ────────────────────────────────────────────────────────
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.sgpj_vpc.id

  tags = { Name = "sgpj-igw" }
}

# ── Subnets Públicas ────────────────────────────────────────────────────────
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.sgpj_vpc.id
  cidr_block              = var.public_subnet_a_cidr
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = true

  tags = { Name = "sgpj-subnet-public-a" }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.sgpj_vpc.id
  cidr_block              = var.public_subnet_b_cidr
  availability_zone       = "${var.region}b"
  map_public_ip_on_launch = true

  tags = { Name = "sgpj-subnet-public-b" }
}

# ── Subnets Privadas (Backend) ──────────────────────────────────────────────
resource "aws_subnet" "private_backend_a" {
  vpc_id            = aws_vpc.sgpj_vpc.id
  cidr_block        = var.private_backend_a_cidr
  availability_zone = "${var.region}a"

  tags = { Name = "sgpj-subnet-private-backend-a" }
}

resource "aws_subnet" "private_backend_b" {
  vpc_id            = aws_vpc.sgpj_vpc.id
  cidr_block        = var.private_backend_b_cidr
  availability_zone = "${var.region}b"

  tags = { Name = "sgpj-subnet-private-backend-b" }
}

# ── Subnets Privadas (Banco de Dados) ──────────────────────────────────────
# AZ-a: onde fica a ec2-db e o mount target EFS já existente
resource "aws_subnet" "private_db_a" {
  vpc_id            = aws_vpc.sgpj_vpc.id
  cidr_block        = var.private_db_a_cidr
  availability_zone = "${var.region}a"

  tags = { Name = "sgpj-subnet-private-db-a" }
}

# ── Route Tables ────────────────────────────────────────────────────────────
# Pública → IGW
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.sgpj_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = { Name = "sgpj-rt-public" }
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "public_b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

# ── Subnet Pública (Observabilidade — AZ-c — opcional) ───────────────────────
resource "aws_subnet" "public_obs" {
  count                   = var.enable_observability ? 1 : 0
  vpc_id                  = aws_vpc.sgpj_vpc.id
  cidr_block              = var.public_subnet_obs_cidr
  availability_zone       = "${var.region}c"
  map_public_ip_on_launch = true

  tags = { Name = "sgpj-subnet-public-obs" }
}

resource "aws_route_table_association" "public_obs" {
  count          = var.enable_observability ? 1 : 0
  subnet_id      = aws_subnet.public_obs[0].id
  route_table_id = aws_route_table.public.id
}

# ── NAT Gateway (temporário — remover com: terraform destroy -target=aws_nat_gateway.ngw -target=aws_eip.nat)
resource "aws_eip" "nat" {
  domain = "vpc"
  tags   = { Name = "sgpj-eip-nat" }
}

resource "aws_nat_gateway" "ngw" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public_a.id

  tags       = { Name = "sgpj-ngw-main" }
  depends_on = [aws_internet_gateway.igw]
}

# Privada → NGW (enquanto NAT Gateway existir)
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.sgpj_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.ngw.id
  }

  tags = { Name = "sgpj-rt-private" }
}

resource "aws_route_table_association" "private_backend_a" {
  subnet_id      = aws_subnet.private_backend_a.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_backend_b" {
  subnet_id      = aws_subnet.private_backend_b.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_db_a" {
  subnet_id      = aws_subnet.private_db_a.id
  route_table_id = aws_route_table.private.id
}

# ── NACLs ───────────────────────────────────────────────────────────────────
resource "aws_network_acl" "public" {
  vpc_id     = aws_vpc.sgpj_vpc.id
  subnet_ids = [aws_subnet.public_a.id, aws_subnet.public_b.id]

  ingress {
    rule_no    = 100
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 80
    to_port    = 80
  }

  ingress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 22
    to_port    = 22
  }

  # Portas efêmeras (respostas TCP)
  ingress {
    rule_no    = 120
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  ingress {
    rule_no    = 130
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 443
    to_port    = 443
  }

  egress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = { Name = "sgpj-nacl-public" }
}

resource "aws_network_acl" "private" {
  vpc_id = aws_vpc.sgpj_vpc.id
  subnet_ids = [
    aws_subnet.private_backend_a.id,
    aws_subnet.private_backend_b.id,
    aws_subnet.private_db_a.id
  ]

  # Tráfego interno da VPC
  ingress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = var.vpc_cidr
    from_port  = 0
    to_port    = 0
  }

  # Portas efêmeras — respostas do NAT Gateway
  ingress {
    rule_no    = 110
    protocol   = "tcp"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 1024
    to_port    = 65535
  }

  egress {
    rule_no    = 100
    protocol   = "-1"
    action     = "allow"
    cidr_block = "0.0.0.0/0"
    from_port  = 0
    to_port    = 0
  }

  tags = { Name = "sgpj-nacl-private" }
}
