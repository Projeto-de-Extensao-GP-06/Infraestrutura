#!/bin/bash
set -e

echo "=== LocalStack Full Infrastructure Initialization ==="

# Configurações
ENDPOINT_URL="http://localhost:4566"
REGION="us-east-1"
AWS_ACCESS_KEY_ID="test"
AWS_SECRET_ACCESS_KEY="test"
VPC_CIDR="10.0.0.0/16"

export AWS_ACCESS_KEY_ID
export AWS_SECRET_ACCESS_KEY
export AWS_DEFAULT_REGION=$REGION

# Função para aguardar LocalStack estar pronto
wait_for_localstack() {
    echo "Aguardando LocalStack ficar pronto..."
    for i in {1..60}; do
        if curl -s "$ENDPOINT_URL/_localstack/health" | grep -q '"s3": "running"'; then
            echo "LocalStack está pronto!"
            return 0
        fi
        echo "Tentativa $i/60 - aguardando..."
        sleep 2
    done
    echo "Erro: LocalStack não ficou pronto a tempo"
    exit 1
}

# ============================================================
# VPC E NETWORKING
# ============================================================

create_vpc() {
    echo "Criando VPC..."
    VPC_ID=$(aws --endpoint-url=$ENDPOINT_URL ec2 create-vpc \
        --cidr-block $VPC_CIDR \
        --query 'Vpc.VpcId' --output text)
    aws --endpoint-url=$ENDPOINT_URL ec2 create-tags \
        --resources $VPC_ID --tags Key=Name,Value=sgpj-vpc
    aws --endpoint-url=$ENDPOINT_URL ec2 modify-vpc-attribute \
        --vpc-id $VPC_ID --enable-dns-support
    aws --endpoint-url=$ENDPOINT_URL ec2 modify-vpc-attribute \
        --vpc-id $VPC_ID --enable-dns-hostnames
    echo "VPC criada: $VPC_ID"
    export VPC_ID
}

create_internet_gateway() {
    echo "Criando Internet Gateway..."
    IGW_ID=$(aws --endpoint-url=$ENDPOINT_URL ec2 create-internet-gateway \
        --query 'InternetGateway.InternetGatewayId' --output text)
    aws --endpoint-url=$ENDPOINT_URL ec2 create-tags \
        --resources $IGW_ID --tags Key=Name,Value=sgpj-igw
    aws --endpoint-url=$ENDPOINT_URL ec2 attach-internet-gateway \
        --internet-gateway-id $IGW_ID --vpc-id $VPC_ID
    echo "IGW criado: $IGW_ID"
    export IGW_ID
}

create_subnets() {
    echo "Criando Subnets..."
    
    # Public A
    SUBNET_PUBLIC_A=$(aws --endpoint-url=$ENDPOINT_URL ec2 create-subnet \
        --vpc-id $VPC_ID --cidr-block 10.0.1.0/24 \
        --availability-zone us-east-1a \
        --query 'Subnet.SubnetId' --output text)
    aws --endpoint-url=$ENDPOINT_URL ec2 create-tags \
        --resources $SUBNET_PUBLIC_A --tags Key=Name,Value=sgpj-subnet-public-a
    aws --endpoint-url=$ENDPOINT_URL ec2 modify-subnet-attribute \
        --subnet-id $SUBNET_PUBLIC_A --map-public-ip-on-launch
    
    # Public B
    SUBNET_PUBLIC_B=$(aws --endpoint-url=$ENDPOINT_URL ec2 create-subnet \
        --vpc-id $VPC_ID --cidr-block 10.0.2.0/24 \
        --availability-zone us-east-1b \
        --query 'Subnet.SubnetId' --output text)
    aws --endpoint-url=$ENDPOINT_URL ec2 create-tags \
        --resources $SUBNET_PUBLIC_B --tags Key=Name,Value=sgpj-subnet-public-b
    aws --endpoint-url=$ENDPOINT_URL ec2 modify-subnet-attribute \
        --subnet-id $SUBNET_PUBLIC_B --map-public-ip-on-launch
    
    # Private Backend A
    SUBNET_PRIVATE_BACKEND_A=$(aws --endpoint-url=$ENDPOINT_URL ec2 create-subnet \
        --vpc-id $VPC_ID --cidr-block 10.0.11.0/24 \
        --availability-zone us-east-1a \
        --query 'Subnet.SubnetId' --output text)
    aws --endpoint-url=$ENDPOINT_URL ec2 create-tags \
        --resources $SUBNET_PRIVATE_BACKEND_A --tags Key=Name,Value=sgpj-subnet-private-backend-a
    
    # Private Backend B
    SUBNET_PRIVATE_BACKEND_B=$(aws --endpoint-url=$ENDPOINT_URL ec2 create-subnet \
        --vpc-id $VPC_ID --cidr-block 10.0.12.0/24 \
        --availability-zone us-east-1b \
        --query 'Subnet.SubnetId' --output text)
    aws --endpoint-url=$ENDPOINT_URL ec2 create-tags \
        --resources $SUBNET_PRIVATE_BACKEND_B --tags Key=Name,Value=sgpj-subnet-private-backend-b
    
    # Private DB A
    SUBNET_PRIVATE_DB_A=$(aws --endpoint-url=$ENDPOINT_URL ec2 create-subnet \
        --vpc-id $VPC_ID --cidr-block 10.0.21.0/24 \
        --availability-zone us-east-1a \
        --query 'Subnet.SubnetId' --output text)
    aws --endpoint-url=$ENDPOINT_URL ec2 create-tags \
        --resources $SUBNET_PRIVATE_DB_A --tags Key=Name,Value=sgpj-subnet-private-db-a
    
    # Private DB B
    SUBNET_PRIVATE_DB_B=$(aws --endpoint-url=$ENDPOINT_URL ec2 create-subnet \
        --vpc-id $VPC_ID --cidr-block 10.0.22.0/24 \
        --availability-zone us-east-1b \
        --query 'Subnet.SubnetId' --output text)
    aws --endpoint-url=$ENDPOINT_URL ec2 create-tags \
        --resources $SUBNET_PRIVATE_DB_B --tags Key=Name,Value=sgpj-subnet-private-db-b
    
    # Public Obs (AZ-c)
    SUBNET_PUBLIC_OBS=$(aws --endpoint-url=$ENDPOINT_URL ec2 create-subnet \
        --vpc-id $VPC_ID --cidr-block 10.0.3.0/24 \
        --availability-zone us-east-1c \
        --query 'Subnet.SubnetId' --output text)
    aws --endpoint-url=$ENDPOINT_URL ec2 create-tags \
        --resources $SUBNET_PUBLIC_OBS --tags Key=Name,Value=sgpj-subnet-public-obs
    aws --endpoint-url=$ENDPOINT_URL ec2 modify-subnet-attribute \
        --subnet-id $SUBNET_PUBLIC_OBS --map-public-ip-on-launch
    
    echo "Subnets criadas"
    export SUBNET_PUBLIC_A SUBNET_PUBLIC_B SUBNET_PRIVATE_BACKEND_A SUBNET_PRIVATE_BACKEND_B
    export SUBNET_PRIVATE_DB_A SUBNET_PRIVATE_DB_B SUBNET_PUBLIC_OBS
}

create_nat_gateway() {
    echo "Criando NAT Gateway..."
    EIP_ALLOC_ID=$(aws --endpoint-url=$ENDPOINT_URL ec2 allocate-address \
        --domain vpc --query 'AllocationId' --output text)
    aws --endpoint-url=$ENDPOINT_URL ec2 create-tags \
        --resources $EIP_ALLOC_ID --tags Key=Name,Value=sgpj-eip-nat
    
    NAT_GW_ID=$(aws --endpoint-url=$ENDPOINT_URL ec2 create-nat-gateway \
        --subnet-id $SUBNET_PUBLIC_A --allocation-id $EIP_ALLOC_ID \
        --query 'NatGateway.NatGatewayId' --output text)
    aws --endpoint-url=$ENDPOINT_URL ec2 create-tags \
        --resources $NAT_GW_ID --tags Key=Name,Value=sgpj-ngw-main
    
    # Aguardar NAT Gateway ficar disponível
    echo "Aguardando NAT Gateway..."
    aws --endpoint-url=$ENDPOINT_URL ec2 wait nat-gateway-available --nat-gateway-ids $NAT_GW_ID
    
    echo "NAT Gateway criado: $NAT_GW_ID"
    export NAT_GW_ID EIP_ALLOC_ID
}

create_route_tables() {
    echo "Criando Route Tables..."
    
    # Public Route Table
    RT_PUBLIC=$(aws --endpoint-url=$ENDPOINT_URL ec2 create-route-table \
        --vpc-id $VPC_ID --query 'RouteTable.RouteTableId' --output text)
    aws --endpoint-url=$ENDPOINT_URL ec2 create-tags \
        --resources $RT_PUBLIC --tags Key=Name,Value=sgpj-rt-public
    aws --endpoint-url=$ENDPOINT_URL ec2 create-route \
        --route-table-id $RT_PUBLIC --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID
    
    # Associar subnets públicas
    aws --endpoint-url=$ENDPOINT_URL ec2 associate-route-table \
        --subnet-id $SUBNET_PUBLIC_A --route-table-id $RT_PUBLIC
    aws --endpoint-url=$ENDPOINT_URL ec2 associate-route-table \
        --subnet-id $SUBNET_PUBLIC_B --route-table-id $RT_PUBLIC
    aws --endpoint-url=$ENDPOINT_URL ec2 associate-route-table \
        --subnet-id $SUBNET_PUBLIC_OBS --route-table-id $RT_PUBLIC
    
    # Private Route Table
    RT_PRIVATE=$(aws --endpoint-url=$ENDPOINT_URL ec2 create-route-table \
        --vpc-id $VPC_ID --query 'RouteTable.RouteTableId' --output text)
    aws --endpoint-url=$ENDPOINT_URL ec2 create-tags \
        --resources $RT_PRIVATE --tags Key=Name,Value=sgpj-rt-private
    aws --endpoint-url=$ENDPOINT_URL ec2 create-route \
        --route-table-id $RT_PRIVATE --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $NAT_GW_ID
    
    # Associar subnets privadas
    aws --endpoint-url=$ENDPOINT_URL ec2 associate-route-table \
        --subnet-id $SUBNET_PRIVATE_BACKEND_A --route-table-id $RT_PRIVATE
    aws --endpoint-url=$ENDPOINT_URL ec2 associate-route-table \
        --subnet-id $SUBNET_PRIVATE_BACKEND_B --route-table-id $RT_PRIVATE
    aws --endpoint-url=$ENDPOINT_URL ec2 associate-route-table \
        --subnet-id $SUBNET_PRIVATE_DB_A --route-table-id $RT_PRIVATE
    aws --endpoint-url=$ENDPOINT_URL ec2 associate-route-table \
        --subnet-id $SUBNET_PRIVATE_DB_B --route-table-id $RT_PRIVATE
    
    echo "Route Tables criadas"
    export RT_PUBLIC RT_PRIVATE
}

create_nacls() {
    echo "Criando NACLs..."
    
    # NACL Pública
    NACL_PUBLIC=$(aws --endpoint-url=$ENDPOINT_URL ec2 create-network-acl \
        --vpc-id $VPC_ID --query 'NetworkAcl.NetworkAclId' --output text)
    aws --endpoint-url=$ENDPOINT_URL ec2 create-tags \
        --resources $NACL_PUBLIC --tags Key=Name,Value=sgpj-nacl-public
    
    # Regras ingress pública
    aws --endpoint-url=$ENDPOINT_URL ec2 create-network-acl-entry \
        --network-acl-id $NACL_PUBLIC --rule-number 100 --protocol tcp --rule-action allow \
        --cidr-block 0.0.0.0/0 --port-range From=80,To=80 --ingress
    aws --endpoint-url=$ENDPOINT_URL ec2 create-network-acl-entry \
        --network-acl-id $NACL_PUBLIC --rule-number 110 --protocol tcp --rule-action allow \
        --cidr-block 0.0.0.0/0 --port-range From=22,To=22 --ingress
    aws --endpoint-url=$ENDPOINT_URL ec2 create-network-acl-entry \
        --network-acl-id $NACL_PUBLIC --rule-number 120 --protocol tcp --rule-action allow \
        --cidr-block 0.0.0.0/0 --port-range From=1024,To=65535 --ingress
    aws --endpoint-url=$ENDPOINT_URL ec2 create-network-acl-entry \
        --network-acl-id $NACL_PUBLIC --rule-number 130 --protocol tcp --rule-action allow \
        --cidr-block 0.0.0.0/0 --port-range From=443,To=443 --ingress
    aws --endpoint-url=$ENDPOINT_URL ec2 create-network-acl-entry \
        --network-acl-id $NACL_PUBLIC --rule-number 100 --protocol -1 --rule-action allow \
        --cidr-block 0.0.0.0/0 --egress
    
    # Associar subnets públicas
    aws --endpoint-url=$ENDPOINT_URL ec2 replace-network-acl-association \
        --association-id $(aws --endpoint-url=$ENDPOINT_URL ec2 describe-network-acls \
        --filters Name=vpc-id,Values=$VPC_ID Name=association.subnet-id,Values=$SUBNET_PUBLIC_A \
        --query 'NetworkAcls[0].Associations[0].NetworkAclAssociationId' --output text) \
        --network-acl-id $NACL_PUBLIC
    aws --endpoint-url=$ENDPOINT_URL ec2 replace-network-acl-association \
        --association-id $(aws --endpoint-url=$ENDPOINT_URL ec2 describe-network-acls \
        --filters Name=vpc-id,Values=$VPC_ID Name=association.subnet-id,Values=$SUBNET_PUBLIC_B \
        --query 'NetworkAcls[0].Associations[0].NetworkAclAssociationId' --output text) \
        --network-acl-id $NACL_PUBLIC
    
    # NACL Privada
    NACL_PRIVATE=$(aws --endpoint-url=$ENDPOINT_URL ec2 create-network-acl \
        --vpc-id $VPC_ID --query 'NetworkAcl.NetworkAclId' --output text)
    aws --endpoint-url=$ENDPOINT_URL ec2 create-tags \
        --resources $NACL_PRIVATE --tags Key=Name,Value=sgpj-nacl-private
    
    # Regras ingress privada
    aws --endpoint-url=$ENDPOINT_URL ec2 create-network-acl-entry \
        --network-acl-id $NACL_PRIVATE --rule-number 100 --protocol -1 --rule-action allow \
        --cidr-block $VPC_CIDR --ingress
    aws --endpoint-url=$ENDPOINT_URL ec2 create-network-acl-entry \
        --network-acl-id $NACL_PRIVATE --rule-number 110 --protocol tcp --rule-action allow \
        --cidr-block 0.0.0.0/0 --port-range From=1024,To=65535 --ingress
    aws --endpoint-url=$ENDPOINT_URL ec2 create-network-acl-entry \
        --network-acl-id $NACL_PRIVATE --rule-number 100 --protocol -1 --rule-action allow \
        --cidr-block 0.0.0.0/0 --egress
    
    # Associar subnets privadas
    for SUBNET in $SUBNET_PRIVATE_BACKEND_A $SUBNET_PRIVATE_BACKEND_B $SUBNET_PRIVATE_DB_A $SUBNET_PRIVATE_DB_B; do
        ASSOC_ID=$(aws --endpoint-url=$ENDPOINT_URL ec2 describe-network-acls \
            --filters Name=vpc-id,Values=$VPC_ID Name=association.subnet-id,Values=$SUBNET \
            --query 'NetworkAcls[0].Associations[0].NetworkAclAssociationId' --output text)
        aws --endpoint-url=$ENDPOINT_URL ec2 replace-network-acl-association \
            --association-id $ASSOC_ID --network-acl-id $NACL_PRIVATE
    done
    
    echo "NACLs criadas"
    export NACL_PUBLIC NACL_PRIVATE
}

# ============================================================
# SECURITY GROUPS
# ============================================================

create_security_groups() {
    echo "Criando Security Groups..."
    
    # ALB SG
    SG_ALB=$(aws --endpoint-url=$ENDPOINT_URL ec2 create-security-group \
        --group-name alb --description "Security group do Load Balancer" --vpc-id $VPC_ID \
        --query 'GroupId' --output text)
    aws --endpoint-url=$ENDPOINT_URL ec2 authorize-security-group-ingress \
        --group-id $SG_ALB --protocol tcp --port 80 --cidr 0.0.0.0/0
    aws --endpoint-url=$ENDPOINT_URL ec2 authorize-security-group-egress \
        --group-id $SG_ALB --protocol -1 --cidr 0.0.0.0/0
    
    # App SG (Public)
    SG_APP=$(aws --endpoint-url=$ENDPOINT_URL ec2 create-security-group \
        --group-name app-public --description "Security group das instancias de aplicacao publica" --vpc-id $VPC_ID \
        --query 'GroupId' --output text)
    aws --endpoint-url=$ENDPOINT_URL ec2 authorize-security-group-ingress \
        --group-id $SG_APP --protocol tcp --port 22 --cidr 0.0.0.0/0
    aws --endpoint-url=$ENDPOINT_URL ec2 authorize-security-group-ingress \
        --group-id $SG_APP --protocol tcp --port 80 --cidr 0.0.0.0/0
    aws --endpoint-url=$ENDPOINT_URL ec2 authorize-security-group-ingress \
        --group-id $SG_APP --protocol tcp --port 9100 --cidr $VPC_CIDR
    aws --endpoint-url=$ENDPOINT_URL ec2 authorize-security-group-ingress \
        --group-id $SG_APP --protocol tcp --port 4317 --cidr $VPC_CIDR
    aws --endpoint-url=$ENDPOINT_URL ec2 authorize-security-group-ingress \
        --group-id $SG_APP --protocol tcp --port 4318 --cidr $VPC_CIDR
    aws --endpoint-url=$ENDPOINT_URL ec2 authorize-security-group-egress \
        --group-id $SG_APP --protocol -1 --cidr 0.0.0.0/0
    
    # Backend SG (Private)
    SG_BACKEND=$(aws --endpoint-url=$ENDPOINT_URL ec2 create-security-group \
        --group-name backend-private --description "Security group das instancias de backend privadas" --vpc-id $VPC_ID \
        --query 'GroupId' --output text)
    aws --endpoint-url=$ENDPOINT_URL ec2 authorize-security-group-ingress \
        --group-id $SG_BACKEND --protocol tcp --port 22 --cidr $VPC_CIDR
    aws --endpoint-url=$ENDPOINT_URL ec2 authorize-security-group-ingress \
        --group-id $SG_BACKEND --protocol tcp --port 8080 --cidr $VPC_CIDR
    aws --endpoint-url=$ENDPOINT_URL ec2 authorize-security-group-ingress \
        --group-id $SG_BACKEND --protocol tcp --port 9100 --cidr $VPC_CIDR
    aws --endpoint-url=$ENDPOINT_URL ec2 authorize-security-group-egress \
        --group-id $SG_BACKEND --protocol -1 --cidr 0.0.0.0/0
    
    # DB SG (Private)
    SG_DB=$(aws --endpoint-url=$ENDPOINT_URL ec2 create-security-group \
        --group-name db-private --description "Security group da instancia de banco de dados" --vpc-id $VPC_ID \
        --query 'GroupId' --output text)
    aws --endpoint-url=$ENDPOINT_URL ec2 authorize-security-group-ingress \
        --group-id $SG_DB --protocol tcp --port 3306 --source-group $SG_BACKEND
    aws --endpoint-url=$ENDPOINT_URL ec2 authorize-security-group-ingress \
        --group-id $SG_DB --protocol tcp --port 22 --cidr $VPC_CIDR
    aws --endpoint-url=$ENDPOINT_URL ec2 authorize-security-group-ingress \
        --group-id $SG_DB --protocol tcp --port 9100 --cidr $VPC_CIDR
    aws --endpoint-url=$ENDPOINT_URL ec2 authorize-security-group-egress \
        --group-id $SG_DB --protocol -1 --cidr 0.0.0.0/0
    
    # Observability SG
    SG_OBS=$(aws --endpoint-url=$ENDPOINT_URL ec2 create-security-group \
        --group-name observability --description "Security group da instancia dedicada de observabilidade" --vpc-id $VPC_ID \
        --query 'GroupId' --output text)
    aws --endpoint-url=$ENDPOINT_URL ec2 authorize-security-group-ingress \
        --group-id $SG_OBS --protocol tcp --port 22 --cidr 0.0.0.0/0
    aws --endpoint-url=$ENDPOINT_URL ec2 authorize-security-group-ingress \
        --group-id $SG_OBS --protocol tcp --port 9090 --cidr 0.0.0.0/0
    aws --endpoint-url=$ENDPOINT_URL ec2 authorize-security-group-ingress \
        --group-id $SG_OBS --protocol tcp --port 3001 --cidr 0.0.0.0/0
    aws --endpoint-url=$ENDPOINT_URL ec2 authorize-security-group-ingress \
        --group-id $SG_OBS --protocol tcp --port 9093 --cidr 0.0.0.0/0
    aws --endpoint-url=$ENDPOINT_URL ec2 authorize-security-group-ingress \
        --group-id $SG_OBS --protocol tcp --port 3100 --cidr $VPC_CIDR
    aws --endpoint-url=$ENDPOINT_URL ec2 authorize-security-group-ingress \
        --group-id $SG_OBS --protocol tcp --port 4317 --cidr $VPC_CIDR
    aws --endpoint-url=$ENDPOINT_URL ec2 authorize-security-group-ingress \
        --group-id $SG_OBS --protocol tcp --port 4318 --cidr $VPC_CIDR
    aws --endpoint-url=$ENDPOINT_URL ec2 authorize-security-group-ingress \
        --group-id $SG_OBS --protocol tcp --port 3200 --cidr $VPC_CIDR
    aws --endpoint-url=$ENDPOINT_URL ec2 authorize-security-group-ingress \
        --group-id $SG_OBS --protocol tcp --port 9100 --cidr $VPC_CIDR
    aws --endpoint-url=$ENDPOINT_URL ec2 authorize-security-group-egress \
        --group-id $SG_OBS --protocol -1 --cidr 0.0.0.0/0
    
    # EFS SG
    SG_EFS=$(aws --endpoint-url=$ENDPOINT_URL ec2 create-security-group \
        --group-name efs --description "Security group do EFS - NFS restrito a VPC" --vpc-id $VPC_ID \
        --query 'GroupId' --output text)
    aws --endpoint-url=$ENDPOINT_URL ec2 authorize-security-group-ingress \
        --group-id $SG_EFS --protocol tcp --port 2049 --cidr $VPC_CIDR
    aws --endpoint-url=$ENDPOINT_URL ec2 authorize-security-group-egress \
        --group-id $SG_EFS --protocol -1 --cidr 0.0.0.0/0
    
    # RDS SG
    SG_RDS=$(aws --endpoint-url=$ENDPOINT_URL ec2 create-security-group \
        --group-name rds-mysql --description "Security group do RDS MySQL" --vpc-id $VPC_ID \
        --query 'GroupId' --output text)
    aws --endpoint-url=$ENDPOINT_URL ec2 authorize-security-group-ingress \
        --group-id $SG_RDS --protocol tcp --port 3306 --source-group $SG_BACKEND
    aws --endpoint-url=$ENDPOINT_URL ec2 authorize-security-group-ingress \
        --group-id $SG_RDS --protocol tcp --port 3306 --source-group $SG_DB
    aws --endpoint-url=$ENDPOINT_URL ec2 authorize-security-group-egress \
        --group-id $SG_RDS --protocol -1 --cidr 0.0.0.0/0
    
    echo "Security Groups criados"
    export SG_ALB SG_APP SG_BACKEND SG_DB SG_OBS SG_EFS SG_RDS
}

# ============================================================
# EC2 INSTANCES
# ============================================================

create_key_pair() {
    echo "Criando Key Pair..."
    aws --endpoint-url=$ENDPOINT_URL ec2 create-key-pair \
        --key-name Key-All --query 'KeyMaterial' --output text > /tmp/Key-All.pem 2>/dev/null || true
    chmod 400 /tmp/Key-All.pem 2>/dev/null || true
}

create_ec2_instances() {
    echo "Criando instâncias EC2..."
    
    # Usar AMI Ubuntu 22.04 para us-east-1
    AMI_ID="ami-0c02fb55956c7d316"  # Ubuntu 22.04 LTS us-east-1
    INSTANCE_TYPE="t3.micro"
    
    # User data simples
    USER_DATA=$(cat <<'EOF'
#!/bin/bash
apt-get update -y
apt-get install -y nginx docker.io awscli
systemctl enable nginx
systemctl start nginx
usermod -aG docker ubuntu
EOF
    )
    USER_DATA_B64=$(echo "$USER_DATA" | base64 -w 0)
    
    # App A (Public)
    INSTANCE_APP_A=$(aws --endpoint-url=$ENDPOINT_URL ec2 run-instances \
        --image-id $AMI_ID --instance-type $INSTANCE_TYPE \
        --subnet-id $SUBNET_PUBLIC_A --security-group-ids $SG_APP \
        --key-name Key-All --associate-public-ip-address \
        --user-data $USER_DATA_B64 \
        --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=ec2-app-a}]' \
        --query 'Instances[0].InstanceId' --output text)
    
    # App B (Public)
    INSTANCE_APP_B=$(aws --endpoint-url=$ENDPOINT_URL ec2 run-instances \
        --image-id $AMI_ID --instance-type $INSTANCE_TYPE \
        --subnet-id $SUBNET_PUBLIC_B --security-group-ids $SG_APP \
        --key-name Key-All --associate-public-ip-address \
        --user-data $USER_DATA_B64 \
        --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=ec2-app-b}]' \
        --query 'Instances[0].InstanceId' --output text)
    
    # Backend A (Private)
    INSTANCE_BACKEND_A=$(aws --endpoint-url=$ENDPOINT_URL ec2 run-instances \
        --image-id $AMI_ID --instance-type $INSTANCE_TYPE \
        --subnet-id $SUBNET_PRIVATE_BACKEND_A --security-group-ids $SG_BACKEND \
        --key-name Key-All \
        --user-data $USER_DATA_B64 \
        --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=ec2-backend-a}]' \
        --query 'Instances[0].InstanceId' --output text)
    
    # Backend B (Private)
    INSTANCE_BACKEND_B=$(aws --endpoint-url=$ENDPOINT_URL ec2 run-instances \
        --image-id $AMI_ID --instance-type $INSTANCE_TYPE \
        --subnet-id $SUBNET_PRIVATE_BACKEND_B --security-group-ids $SG_BACKEND \
        --key-name Key-All \
        --user-data $USER_DATA_B64 \
        --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=ec2-backend-b}]' \
        --query 'Instances[0].InstanceId' --output text)
    
    # DB (Private)
    INSTANCE_DB=$(aws --endpoint-url=$ENDPOINT_URL ec2 run-instances \
        --image-id $AMI_ID --instance-type $INSTANCE_TYPE \
        --subnet-id $SUBNET_PRIVATE_DB_A --security-group-ids $SG_DB \
        --key-name Key-All \
        --user-data $USER_DATA_B64 \
        --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=ec2-db}]' \
        --query 'Instances[0].InstanceId' --output text)
    
    # Observability (Public)
    INSTANCE_OBS=$(aws --endpoint-url=$ENDPOINT_URL ec2 run-instances \
        --image-id $AMI_ID --instance-type $INSTANCE_TYPE \
        --subnet-id $SUBNET_PUBLIC_OBS --security-group-ids $SG_OBS \
        --key-name Key-All --associate-public-ip-address \
        --user-data $USER_DATA_B64 \
        --block-device-mappings '[{"DeviceName":"/dev/sda1","Ebs":{"VolumeSize":20,"VolumeType":"gp3"}}]' \
        --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=ec2-observability}]' \
        --query 'Instances[0].InstanceId' --output text)
    
    echo "Aguardando instâncias ficarem running..."
    aws --endpoint-url=$ENDPOINT_URL ec2 wait instance-running \
        --instance-ids $INSTANCE_APP_A $INSTANCE_APP_B $INSTANCE_BACKEND_A $INSTANCE_BACKEND_B $INSTANCE_DB $INSTANCE_OBS
    
    echo "Instâncias EC2 criadas"
    export INSTANCE_APP_A INSTANCE_APP_B INSTANCE_BACKEND_A INSTANCE_BACKEND_B INSTANCE_DB INSTANCE_OBS
}

# ============================================================
# RDS
# ============================================================

create_rds() {
    echo "Criando RDS MySQL..."
    
    # DB Subnet Group
    aws --endpoint-url=$ENDPOINT_URL rds create-db-subnet-group \
        --db-subnet-group-name sgpj-rds-subnet-group \
        --db-subnet-group-description "Subnet group do RDS MySQL" \
        --subnet-ids $SUBNET_PRIVATE_DB_A $SUBNET_PRIVATE_DB_B \
        --tags Key=Name,Value=sgpj-rds-subnet-group
    
    # RDS Instance
    aws --endpoint-url=$ENDPOINT_URL rds create-db-instance \
        --db-instance-identifier sgpj-mysql \
        --engine mysql --engine-version 8.0 \
        --db-instance-class db.t3.micro \
        --allocated-storage 20 --max-allocated-storage 100 \
        --storage-type gp3 --storage-encrypted \
        --db-name sgpjdb --master-username admin --master-user-password admin123 \
        --db-subnet-group-name sgpj-rds-subnet-group \
        --vpc-security-group-ids $SG_RDS \
        --multi-az false --publicly-accessible false \
        --deletion-protection false --skip-final-snapshot \
        --backup-retention-period 7 \
        --backup-window "03:00-04:00" \
        --maintenance-window "Mon:04:00-Mon:05:00" \
        --tags Key=Name,Value=sgpj-rds-mysql
    
    echo "RDS criado (aguardando ficar available em background)"
}

# ============================================================
# EFS
# ============================================================

create_efs() {
    echo "Criando EFS..."
    
    EFS_ID=$(aws --endpoint-url=$ENDPOINT_URL efs create-file-system \
        --creation-token sgpj-app-efs --encrypted \
        --tags Key=Name,Value=sgpj-app-efs \
        --query 'FileSystemId' --output text)
    
    # Mount targets
    aws --endpoint-url=$ENDPOINT_URL efs create-mount-target \
        --file-system-id $EFS_ID --subnet-id $SUBNET_PRIVATE_BACKEND_A \
        --security-groups $SG_EFS
    aws --endpoint-url=$ENDPOINT_URL efs create-mount-target \
        --file-system-id $EFS_ID --subnet-id $SUBNET_PRIVATE_BACKEND_B \
        --security-groups $SG_EFS
    
    echo "EFS criado: $EFS_ID"
    export EFS_ID
}

# ============================================================
# ALB
# ============================================================

create_alb() {
    echo "Criando ALB..."
    
    ALB_ARN=$(aws --endpoint-url=$ENDPOINT_URL elbv2 create-load-balancer \
        --name alb-app --type application --scheme internet-facing \
        --security-groups $SG_ALB \
        --subnets $SUBNET_PUBLIC_A $SUBNET_PUBLIC_B \
        --tags Key=Name,Value=alb-app \
        --query 'LoadBalancers[0].LoadBalancerArn' --output text)
    
    TG_ARN=$(aws --endpoint-url=$ENDPOINT_URL elbv2 create-target-group \
        --name tg-app --protocol HTTP --port 80 --vpc-id $VPC_ID \
        --health-check-path "/" --health-check-protocol HTTP \
        --health-check-interval-seconds 30 --health-check-timeout-seconds 5 \
        --healthy-threshold-count 2 --unhealthy-threshold-count 2 \
        --matcher HttpCode=200 \
        --tags Key=Name,Value=tg-app \
        --query 'TargetGroups[0].TargetGroupArn' --output text)
    
    # Registrar targets
    aws --endpoint-url=$ENDPOINT_URL elbv2 register-targets \
        --target-group-arn $TG_ARN \
        --targets Id=$INSTANCE_APP_A,Port=80 Id=$INSTANCE_APP_B,Port=80
    
    # Listener
    aws --endpoint-url=$ENDPOINT_URL elbv2 create-listener \
        --load-balancer-arn $ALB_ARN --protocol HTTP --port 80 \
        --default-actions Type=forward,TargetGroupArn=$TG_ARN
    
    echo "ALB criado: $ALB_ARN"
    export ALB_ARN TG_ARN
}

# ============================================================
# IAM ROLES
# ============================================================

create_iam_roles() {
    echo "Criando IAM Roles..."
    
    # Glue Crawler Role
    cat > /tmp/glue-trust-policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Principal": {"Service": "glue.amazonaws.com"},
        "Action": "sts:AssumeRole"
    }]
}
EOF
    
    aws --endpoint-url=$ENDPOINT_URL iam create-role \
        --role-name sgpj-glue-crawler-role \
        --assume-role-policy-document file:///tmp/glue-trust-policy.json 2>/dev/null || true
    
    cat > /tmp/glue-crawler-policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": ["s3:GetObject","s3:PutObject","s3:DeleteObject","s3:ListBucket","s3:GetBucketLocation"],
            "Resource": ["arn:aws:s3:::sgpj-bronze","arn:aws:s3:::sgpj-bronze/*","arn:aws:s3:::sgpj-silver","arn:aws:s3:::sgpj-silver/*","arn:aws:s3:::sgpj-gold","arn:aws:s3:::sgpj-gold/*"]
        },
        {
            "Effect": "Allow",
            "Action": ["glue:*","logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents"],
            "Resource": "*"
        }
    ]
}
EOF
    
    aws --endpoint-url=$ENDPOINT_URL iam put-role-policy \
        --role-name sgpj-glue-crawler-role --policy-name sgpj-glue-crawler-policy \
        --policy-document file:///tmp/glue-crawler-policy.json
    
    # Glue Job Role
    aws --endpoint-url=$ENDPOINT_URL iam create-role \
        --role-name sgpj-glue-job-role \
        --assume-role-policy-document file:///tmp/glue-trust-policy.json 2>/dev/null || true
    
    cat > /tmp/glue-job-policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": ["s3:GetObject","s3:PutObject","s3:DeleteObject","s3:ListBucket","s3:GetBucketLocation"],
            "Resource": ["arn:aws:s3:::sgpj-bronze","arn:aws:s3:::sgpj-bronze/*","arn:aws:s3:::sgpj-silver","arn:aws:s3:::sgpj-silver/*","arn:aws:s3:::sgpj-gold","arn:aws:s3:::sgpj-gold/*"]
        },
        {
            "Effect": "Allow",
            "Action": ["glue:*","logs:CreateLogGroup","logs:CreateLogStream","logs:PutLogEvents","s3:GetObject","s3:PutObject"],
            "Resource": "*"
        }
    ]
}
EOF
    
    aws --endpoint-url=$ENDPOINT_URL iam put-role-policy \
        --role-name sgpj-glue-job-role --policy-name sgpj-glue-job-policy \
        --policy-document file:///tmp/glue-job-policy.json
    
    # Observability EC2 Role
    cat > /tmp/obs-trust-policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Principal": {"Service": "ec2.amazonaws.com"},
        "Action": "sts:AssumeRole"
    }]
}
EOF
    
    aws --endpoint-url=$ENDPOINT_URL iam create-role \
        --role-name sgpj-observability-ec2-role \
        --assume-role-policy-document file:///tmp/obs-trust-policy.json 2>/dev/null || true
    
    cat > /tmp/obs-policy.json <<EOF
{
    "Version": "2012-10-17",
    "Statement": [{
        "Effect": "Allow",
        "Action": ["cloudwatch:GetMetricData","cloudwatch:GetMetricStatistics","cloudwatch:ListMetrics","tag:GetResources","ec2:DescribeInstances","elasticloadbalancing:DescribeLoadBalancers","elasticloadbalancing:DescribeTargetGroups","rds:DescribeDBInstances","elasticfilesystem:DescribeFileSystems"],
        "Resource": "*"
    }]
}
EOF
    
    aws --endpoint-url=$ENDPOINT_URL iam put-role-policy \
        --role-name sgpj-observability-ec2-role --policy-name sgpj-cloudwatch-exporter-read \
        --policy-document file:///tmp/obs-policy.json
    
    aws --endpoint-url=$ENDPOINT_URL iam create-instance-profile \
        --instance-profile-name sgpj-observability-ec2-profile 2>/dev/null || true
    aws --endpoint-url=$ENDPOINT_URL iam add-role-to-instance-profile \
        --instance-profile-name sgpj-observability-ec2-profile \
        --role-name sgpj-observability-ec2-role 2>/dev/null || true
    
    echo "IAM Roles criadas"
}

# ============================================================
# S3 BUCKETS (Data Lake)
# ============================================================

create_s3_buckets() {
    echo "Criando buckets S3 Data Lake..."
    
    for BUCKET in sgpj-bronze sgpj-silver sgpj-gold; do
        aws --endpoint-url=$ENDPOINT_URL s3api create-bucket \
            --bucket $BUCKET --region $REGION \
            --create-bucket-configuration LocationConstraint=$REGION 2>/dev/null || true
        
        aws --endpoint-url=$ENDPOINT_URL s3api put-bucket-versioning \
            --bucket $BUCKET --versioning-configuration Status=Enabled
        
        aws --endpoint-url=$ENDPOINT_URL s3api put-bucket-encryption \
            --bucket $BUCKET \
            --server-side-encryption-configuration '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
    done
    
    echo "Buckets S3 criados"
}

# ============================================================
# GLUE DATABASES & CRAWLERS
# ============================================================

create_glue_resources() {
    echo "Criando recursos Glue..."
    
    # Databases
    for DB in sgpj_bronze sgpj_silver sgpj_gold; do
        DESC="Database for $DB layer"
        aws --endpoint-url=$ENDPOINT_URL glue create-database \
            --database-input "{\"Name\":\"$DB\",\"Description\":\"$DESC\"}" 2>/dev/null || echo "Database $DB já existe"
    done
    
    # Crawlers
    GLUE_ROLE_ARN="arn:aws:iam::000000000000:role/sgpj-glue-crawler-role"
    
    for LAYER in bronze silver gold; do
        DB_NAME="sgpj_${LAYER}"
        BUCKET_NAME="sgpj-${LAYER}"
        CRAWLER_NAME="sgpj-${LAYER}-crawler"
        
        aws --endpoint-url=$ENDPOINT_URL glue create-crawler \
            --name $CRAWLER_NAME --role $GLUE_ROLE_ARN \
            --database-name $DB_NAME \
            --description "Crawler for ${LAYER} layer" \
            --targets "{\"S3Targets\":[{\"Path\":\"s3://${BUCKET_NAME}/\"}]}" \
            --schema-change-policy '{"UpdateBehavior":"UPDATE_IN_DATABASE","DeleteBehavior":"LOG"}' \
            --recrawl-policy '{"RecrawlBehavior":"CRAWL_EVERYTHING"}' \
            --configuration '{"Version":1.0,"CrawlerOutput":{"Partitions":{"AddOrUpdateBehavior":"InheritFromTable"}}}' \
            --tags "Name=${CRAWLER_NAME},Environment=data-lake,Layer=${LAYER}" 2>/dev/null || echo "Crawler $CRAWLER_NAME já existe"
    done
    
    echo "Recursos Glue criados"
}

# ============================================================
# SAMPLE DATA & ETL SCRIPTS
# ============================================================

upload_sample_data() {
    echo "Enviando dados de exemplo e scripts ETL..."
    
    mkdir -p /tmp/sample_data/bronze /tmp/sample_data/silver /tmp/sample_data/gold /tmp/etl_scripts
    
    # Dados bronze
    cat > /tmp/sample_data/bronze/events.json <<EOF
{"event_id": "1", "user_id": "100", "event_type": "click", "timestamp": "2024-01-15T10:30:00Z", "page": "/home"}
{"event_id": "2", "user_id": "101", "event_type": "view", "timestamp": "2024-01-15T10:31:00Z", "page": "/product/123"}
{"event_id": "3", "user_id": "100", "event_type": "purchase", "timestamp": "2024-01-15T10:35:00Z", "page": "/checkout", "amount": 99.90}
EOF
    
    # Dados silver
    cat > /tmp/sample_data/silver/events_cleaned.parquet <<EOF
event_id,user_id,event_type,timestamp,page,amount
1,100,click,2024-01-15T10:30:00Z,/home,
2,101,view,2024-01-15T10:31:00Z,/product/123,
3,100,purchase,2024-01-15T10:35:00Z,/checkout,99.90
EOF
    
    # Dados gold
    cat > /tmp/sample_data/gold/daily_summary.csv <<EOF
date,total_events,unique_users,total_revenue
2024-01-15,3,2,99.90
EOF
    
    # Upload
    aws --endpoint-url=$ENDPOINT_URL s3 cp /tmp/sample_data/bronze/ s3://sgpj-bronze/ --recursive
    aws --endpoint-url=$ENDPOINT_URL s3 cp /tmp/sample_data/silver/ s3://sgpj-silver/ --recursive
    aws --endpoint-url=$ENDPOINT_URL s3 cp /tmp/sample_data/gold/ s3://sgpj-gold/ --recursive
    
    # Scripts ETL
    cat > /tmp/etl_scripts/bronze_to_silver.py <<'EOF'
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql import functions as F

args = getResolvedOptions(sys.argv, ['JOB_NAME', 'source_bucket', 'target_bucket', 'source_database', 'target_database'])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

source_bucket = args['source_bucket']
target_bucket = args['target_bucket']

dyf = glueContext.create_dynamic_frame.from_options(
    connection_type="s3", connection_options={"paths": [f"s3://{source_bucket}/"]}, format="json"
)

df = dyf.toDF()
df_clean = df.dropDuplicates().na.drop(how="all") \
    .withColumn("_processed_at", F.current_timestamp()) \
    .withColumn("_source_bucket", F.lit(source_bucket))

df_clean.write.mode("overwrite").partitionBy("_processed_at").parquet(f"s3://{target_bucket}/")
print("Bronze to Silver ETL completed!")
job.commit()
EOF
    
    cat > /tmp/etl_scripts/silver_to_gold.py <<'EOF'
import sys
from awsglue.transforms import *
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext
from awsglue.context import GlueContext
from awsglue.job import Job
from pyspark.sql import functions as F

args = getResolvedOptions(sys.argv, ['JOB_NAME', 'source_bucket', 'target_bucket', 'source_database', 'target_database'])

sc = SparkContext()
glueContext = GlueContext(sc)
spark = glueContext.spark_session
job = Job(glueContext)
job.init(args['JOB_NAME'], args)

source_bucket = args['source_bucket']
target_bucket = args['target_bucket']

df = spark.read.parquet(f"s3://{source_bucket}/")

if "event_type" in df.columns and "user_id" in df.columns:
    gold_metrics = df.groupBy("event_type").agg(F.count("*").alias("total_events"), F.countDistinct("user_id").alias("unique_users"))
    if "timestamp" in df.columns:
        daily_metrics = df.withColumn("event_date", F.to_date("timestamp")).groupBy("event_date", "event_type").agg(F.count("*").alias("total_events"), F.countDistinct("user_id").alias("unique_users"))
        daily_metrics.write.mode("overwrite").partitionBy("event_date").parquet(f"s3://{target_bucket}/daily_metrics/")
    gold_metrics.write.mode("overwrite").parquet(f"s3://{target_bucket}/event_summary/")

print("Silver to Gold ETL completed!")
job.commit()
EOF
    
    aws --endpoint-url=$ENDPOINT_URL s3 cp /tmp/etl_scripts/bronze_to_silver.py s3://sgpj-silver/scripts/bronze_to_silver.py
    aws --endpoint-url=$ENDPOINT_URL s3 cp /tmp/etl_scripts/silver_to_gold.py s3://sgpj-gold/scripts/silver_to_gold.py
    
    echo "Dados e scripts enviados"
}

# ============================================================
# CLOUDWATCH DASHBOARD
# ============================================================

create_cloudwatch_dashboard() {
    echo "Criando CloudWatch Dashboard..."
    
    # Note: LocalStack has limited CloudWatch Dashboard support
    # This creates a basic dashboard structure
    cat > /tmp/dashboard.json <<EOF
{
    "widgets": [
        {
            "type": "text",
            "x": 0, "y": 0, "width": 24, "height": 1,
            "properties": {"markdown": "## SGPJ Infrastructure Dashboard (LocalStack)"}
        }
    ]
}
EOF
    
    aws --endpoint-url=$ENDPOINT_URL cloudwatch put-dashboard \
        --dashboard-name SGPJ-Infraestrutura \
        --dashboard-body file:///tmp/dashboard.json 2>/dev/null || echo "Dashboard creation limited in LocalStack"
}

# ============================================================
# LIST RESOURCES
# ============================================================

list_all_resources() {
    echo ""
    echo "=== RECURSOS CRIADOS ==="
    echo ""
    
    echo "VPC:"
    aws --endpoint-url=$ENDPOINT_URL ec2 describe-vpcs --vpc-ids $VPC_ID --query 'Vpcs[0].{VpcId:VpcId,CidrBlock:CidrBlock,State:State}' --output table
    
    echo ""
    echo "Subnets:"
    aws --endpoint-url=$ENDPOINT_URL ec2 describe-subnets --filters Name=vpc-id,Values=$VPC_ID --query 'Subnets[].{SubnetId:SubnetId,CidrBlock:CidrBlock,AZ:AvailabilityZone,Name:Tags[?Key==`Name`].Value|[0]}' --output table
    
    echo ""
    echo "Security Groups:"
    aws --endpoint-url=$ENDPOINT_URL ec2 describe-security-groups --filters Name=vpc-id,Values=$VPC_ID --query 'SecurityGroups[].{GroupId:GroupId,GroupName:GroupName,Description:Description}' --output table
    
    echo ""
    echo "EC2 Instances:"
    aws --endpoint-url=$ENDPOINT_URL ec2 describe-instances --filters Name=vpc-id,Values=$VPC_ID --query 'Reservations[].Instances[].{InstanceId:InstanceId,Type:InstanceType,State:State.Name,Name:Tags[?Key==`Name`].Value|[0],Subnet:SubnetId,PublicIP:PublicIpAddress}' --output table
    
    echo ""
    echo "RDS:"
    aws --endpoint-url=$ENDPOINT_URL rds describe-db-instances --query 'DBInstances[].{DBInstanceIdentifier:DBInstanceIdentifier,Engine:Engine,Status:DBInstanceStatus,Class:DBInstanceClass,Endpoint:Endpoint.Address}' --output table
    
    echo ""
    echo "EFS:"
    aws --endpoint-url=$ENDPOINT_URL efs describe-file-systems --query 'FileSystems[].{FileSystemId:FileSystemId,State:LifeCycleState,Size:SizeInBytes.Value}' --output table
    
    echo ""
    echo "ALB:"
    aws --endpoint-url=$ENDPOINT_URL elbv2 describe-load-balancers --query 'LoadBalancers[].{Name:LoadBalancerName,ARN:LoadBalancerArn,State:State.Code,DNSName:DNSName}' --output table
    
    echo ""
    echo "Target Groups:"
    aws --endpoint-url=$ENDPOINT_URL elbv2 describe-target-groups --query 'TargetGroups[].{Name:TargetGroupName,Protocol:Protocol,Port:Port,VpcId:VpcId}' --output table
    
    echo ""
    echo "IAM Roles:"
    aws --endpoint-url=$ENDPOINT_URL iam list-roles --query 'Roles[?contains(RoleName, `sgpj`)].{RoleName:RoleName,Arn:Arn}' --output table
    
    echo ""
    echo "S3 Buckets:"
    aws --endpoint-url=$ENDPOINT_URL s3 ls
    
    echo ""
    echo "Glue Databases:"
    aws --endpoint-url=$ENDPOINT_URL glue get-databases --query 'DatabaseList[?contains(Name, `sgpj`)].{Name:Name,Description:Description}' --output table
    
    echo ""
    echo "Glue Crawlers:"
    aws --endpoint-url=$ENDPOINT_URL glue get-crawlers --query 'Crawlers[?contains(Name, `sgpj`)].{Name:Name,Role:Role,Database:DatabaseName,State:State}' --output table
}

# ============================================================
# MAIN
# ============================================================

main() {
    wait_for_localstack
    
    echo ""
    echo "=== 1. VPC E NETWORKING ==="
    create_vpc
    create_internet_gateway
    create_subnets
    create_nat_gateway
    create_route_tables
    create_nacls
    
    echo ""
    echo "=== 2. SECURITY GROUPS ==="
    create_security_groups
    
    echo ""
    echo "=== 3. KEY PAIR ==="
    create_key_pair
    
    echo ""
    echo "=== 4. EC2 INSTANCES ==="
    create_ec2_instances
    
    echo ""
    echo "=== 5. RDS ==="
    create_rds
    
    echo ""
    echo "=== 6. EFS ==="
    create_efs
    
    echo ""
    echo "=== 7. ALB ==="
    create_alb
    
    echo ""
    echo "=== 8. IAM ROLES ==="
    create_iam_roles
    
    echo ""
    echo "=== 9. S3 DATA LAKE ==="
    create_s3_buckets
    
    echo ""
    echo "=== 10. GLUE RESOURCES ==="
    create_glue_resources
    
    echo ""
    echo "=== 11. SAMPLE DATA & ETL ==="
    upload_sample_data
    
    echo ""
    echo "=== 12. CLOUDWATCH DASHBOARD ==="
    create_cloudwatch_dashboard
    
    echo ""
    echo "=== 13. LISTAGEM FINAL ==="
    list_all_resources
    
    echo ""
    echo "=== INICIALIZAÇÃO COMPLETA! ==="
    echo ""
    echo "Endpoints principais:"
    echo "  ALB DNS: $(aws --endpoint-url=$ENDPOINT_URL elbv2 describe-load-balancers --query 'LoadBalancers[0].DNSName' --output text 2>/dev/null || echo 'N/A')"
    echo "  RDS Endpoint: $(aws --endpoint-url=$ENDPOINT_URL rds describe-db-instances --db-instance-identifier sgpj-mysql --query 'DBInstances[0].Endpoint.Address' --output text 2>/dev/null || echo 'N/A')"
    echo "  EFS ID: $EFS_ID"
    echo ""
    echo "Para testar:"
    echo "  aws --endpoint-url=$ENDPOINT_URL glue start-crawler --name sgpj-bronze-crawler"
    echo "  aws --endpoint-url=$ENDPOINT_URL glue start-crawler --name sgpj-silver-crawler"
    echo "  aws --endpoint-url=$ENDPOINT_URL glue start-crawler --name sgpj-gold-crawler"
}

main "$@"