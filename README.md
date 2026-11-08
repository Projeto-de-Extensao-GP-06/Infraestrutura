# SGPJ — Infraestrutura como Código (IaC) e Automação

Este repositório contém toda a definição de infraestrutura em nuvem (AWS) e orquestração de servidores para o projeto **SGPJ (Sistema de Gestão de Processos Jurídicos)**.

---

## 🛠️ Tecnologias Utilizadas

* **Terraform:** Provisionamento declarativo de toda a infraestrutura AWS (VPC, Subnets, EC2, EFS, ECR, S3, IAM, Athena, CloudWatch).
* **Ansible:** Gerenciamento de configuração dos servidores, instalação do Docker, montagem de EFS compartilhado e subida dos containers.
* **AWS Services:** VPC, EC2, Application Load Balancer, EFS, S3 Data Lake, ECR, CloudWatch e AWS SSM.
* **GitHub Actions:** Pipeline automatizado de validação de IaC (`terraform fmt`, `terraform validate`, `ansible-lint`).

---

## 📁 Estrutura de Diretórios

```text
infra/
├── .github/workflows/      # Pipelines de CI/CD para validação da infraestrutura
│   └── ci.yml
├── ansible/                # Playbooks e roles de configuração dos servidores
│   ├── inventories/        # Inventários dinâmicos gerados pelo Terraform
│   ├── playbooks/roles/    # Roles modulares (backend, db, nginx, docker, observability)
│   ├── secrets.yml.example # Modelo de variáveis e segredos
│   └── run_ansible.sh      # Script de orquestração local
├── terraform/              # Código de provisionamento AWS
│   ├── compute.tf          # Definição das instâncias EC2 e Load Balancer
│   ├── vpc.tf              # Rede, subnets, NAT Gateway e NACLs
│   ├── efs.tf              # Storage compartilhado (EFS)
│   ├── ecr.tf              # Repositórios de imagens Docker
│   ├── data_lake.tf        # Buckets S3 e infraestrutura de dados
│   ├── terraform.tfvars.example # Variáveis configuráveis de exemplo
│   └── ansible.tf          # Integração automática Terraform ➔ Ansible
└── PASSO_A_PASSO.md        # Guia definitivo para qualquer membro rodar o projeto
```

---

## 🚀 Como Executar

Para subir toda a infraestrutura do zero na sua máquina, consulte o guia passo a passo detalhado:
👉 **[Leia o PASSO_A_PASSO.md](PASSO_A_PASSO.md)**

---

## 🔄 Fluxo de CI/CD da Infraestrutura

* Todo **Pull Request** aberto para as branches `main` ou `develop` ativa o pipeline de validação:
  * `terraform fmt -check`: Garante o padrão oficial de formatação de código.
  * `terraform validate`: Valida a sintaxe e a integridade de todos os recursos.
  * `ansible-lint`: Analisa boas práticas nos playbooks e roles do Ansible.
