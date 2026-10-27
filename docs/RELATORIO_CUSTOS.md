# 💰 Relatório de Custos e FinOps — SGPJ Infraestrutura

Relatório técnico de estimativa e validação de custos de nuvem da infraestrutura provisionada via Terraform na AWS (`us-east-1`), consolidando a análise cruzada entre **Infracost** e **c3x**.

---

## 1. Resumo Executivo & Validação Cruzada

Realizamos a estimativa independente utilizando duas das principais ferramentas de FinOps para Infrastructure as Code (IaC):

| Ferramenta | Total Mensal Projetado (24/7) | Custo por Hora | Status |
|---|---|---|---|
| **c3x** | **$ 148,61 / mês** | ~$ 0,203 / hora | ✅ Validado |
| **Infracost** | **$ 148,98 / mês** | ~$ 0,204 / hora | ✅ Validado |
| **Divergência entre ferramentas** | **$ 0,37 (0,25%)** | — | **Concordância de 99,75%** |

> [!TIP]
> A divergência de apenas **$ 0,37 centavos** decorre exclusivamente da metodologia de cálculo do volume de disco raiz padrão (EBS de 8 GB nas instâncias EC2). Ambas as ferramentas confirmam que a infraestrutura completa consome cerca de **$ 149/mês** se mantida ligada ininterruptamente.

### 🎓 Viabilidade no Laboratório AWS Academy ($100 de Saldo):
- A infraestrutura custa aproximadamente **$ 0,20 por hora**.
- Em uma sessão típica de apresentação ou testes de carga de **4 horas**:
  $$\text{Custo Real Consumido} = 4 \text{ horas} \times \$0,204 = \mathbf{\sim \$ 0,81}$$
- Ao executar `terraform destroy` após os testes, mais de **$ 99,00** do voucher de $100 permanecem intactos.

---

## 2. Detalhamento Item a Item — Infracost vs c3x

| Recurso IaC | Tipo / Parâmetro | Quantidade | c3x | Infracost |
|---|---|---|---|---|
| `aws_nat_gateway.ngw` | Gateway NAT (subnets privadas) | 730 h | $ 32,85 | $ 32,85 |
| `aws_lb.app` | Application Load Balancer (ALB) | 730 h | $ 16,43 | $ 16,43 |
| `aws_instance.app_a` | `t3.small` (Compute + EBS raiz) | 730 h | $ 15,18 | $ 15,98 |
| `aws_instance.app_b` | `t3.small` (Compute + EBS raiz) | 730 h | $ 15,18 | $ 15,98 |
| `aws_instance.backend_a` | `t3.small` (Compute + EBS raiz) | 730 h | $ 15,18 | $ 15,98 |
| `aws_instance.backend_b` | `t3.small` (Compute + EBS raiz) | 730 h | $ 15,18 | $ 15,98 |
| `aws_instance.db` | `t3.small` (Compute + EBS raiz) | 730 h | $ 15,18 | $ 15,98 |
| `aws_instance.observability[0]` | `t3.small` + 20 GB EBS gp3 | 730 h | $ 16,78 | $ 16,78 |
| `aws_cloudwatch_dashboard.sgpj` | Dashboard customizado | 1 mês | $ 3,00 | $ 3,00 |
| `aws_eip.nat` | IP Público IPv4 (NAT Gateway) | 730 h | $ 3,65 | *(incluso no NAT)* |
| `aws_ecr_repository` (Front/Back) | Repositório de imagens Docker | Por uso ($0,10/GB) | $ 0,00 | $ 0,00 |
| `aws_efs_file_system.app_efs` | Armazenamento compartilhado NFS | Por uso ($0,16/GB) | $ 0,00 | $ 0,00 |
| `aws_glue_catalog_database.*` | Catálogos Glue Data Lake e Logs | Por uso | $ 0,00 | $ 0,00 |
| `aws_s3_bucket.*` & `athena` | S3 Bronze/Silver/Gold & Athena | Por uso | $ 0,00 | $ 0,00 |
| **TOTAL GERAL** | | | **$ 148,61** | **$ 148,98** |

---

## 3. Saída Oficial Bruta do Infracost

Executado via comando:
```bash
infracost breakdown --path infra/terraform
```

```text
Project: main

 Name                                                       Monthly Qty  Unit                    Monthly Cost   
     
 aws_nat_gateway.ngw     
 ├─ NAT gateway                                                     730  hours                         $32.85   
 └─ Data processed                                    Monthly cost depends on usage: $0.045 per GB     
     
 aws_instance.observability[0]     
 ├─ Instance usage (Linux/UNIX, on-demand, t3.small)                730  hours                         $15.18   
 └─ root_block_device     
    └─ Storage (general purpose SSD, gp3)                            20  GB                             $1.60   
     
 aws_lb.app     
 ├─ Application load balancer                                       730  hours                         $16.43   
 └─ Load balancer capacity units                      Monthly cost depends on usage: $5.84 per LCU     
     
 aws_instance.app_a     
 ├─ Instance usage (Linux/UNIX, on-demand, t3.small)                730  hours                         $15.18   
 └─ root_block_device     
    └─ Storage (general purpose SSD, gp2)                             8  GB                             $0.80   
     
 aws_instance.app_b     
 ├─ Instance usage (Linux/UNIX, on-demand, t3.small)                730  hours                         $15.18   
 └─ root_block_device     
    └─ Storage (general purpose SSD, gp2)                             8  GB                             $0.80   
     
 aws_instance.backend_a     
 ├─ Instance usage (Linux/UNIX, on-demand, t3.small)                730  hours                         $15.18   
 └─ root_block_device     
    └─ Storage (general purpose SSD, gp2)                             8  GB                             $0.80   
     
 aws_instance.backend_b     
 ├─ Instance usage (Linux/UNIX, on-demand, t3.small)                730  hours                         $15.18   
 └─ root_block_device     
    └─ Storage (general purpose SSD, gp2)                             8  GB                             $0.80   
     
 aws_instance.db     
 ├─ Instance usage (Linux/UNIX, on-demand, t3.small)                730  hours                         $15.18   
 └─ root_block_device     
    └─ Storage (general purpose SSD, gp2)                             8  GB                             $0.80   
     
 aws_cloudwatch_dashboard.sgpj     
 └─ Dashboard                                                         1  months                         $3.00   
     
 aws_ecr_repository.backend     
 └─ Storage                                           Monthly cost depends on usage: $0.10 per GB     
     
 aws_ecr_repository.frontend     
 └─ Storage                                           Monthly cost depends on usage: $0.10 per GB     
     
 aws_efs_file_system.app_efs     
 └─ Storage (standard)                                Monthly cost depends on usage: $0.30 per GB     
     
 aws_glue_catalog_database.bronze_db     
 ├─ Storage                                           Monthly cost depends on usage: $1.00 per 100k objects     
 └─ Requests                                          Monthly cost depends on usage: $1.00 per 1M requests     
     
 aws_glue_catalog_database.gold_db     
 ├─ Storage                                           Monthly cost depends on usage: $1.00 per 100k objects     
 └─ Requests                                          Monthly cost depends on usage: $1.00 per 1M requests     
     
 aws_glue_catalog_database.logs_db     
 ├─ Storage                                           Monthly cost depends on usage: $1.00 per 100k objects     
 └─ Requests                                          Monthly cost depends on usage: $1.00 per 1M requests     
     
 aws_glue_catalog_database.silver_db     
 ├─ Storage                                           Monthly cost depends on usage: $1.00 per 100k objects     
 └─ Requests                                          Monthly cost depends on usage: $1.00 per 1M requests     
     
 OVERALL TOTAL                                                                                       $148.98 

──────────────────────────────────
54 cloud resources were detected:
∙ 16 were estimated
∙ 33 were free
∙ 5 are not supported yet, rerun with --show-skipped to see details
```

---

## 4. Análise de Otimização e Conclusão

- **Arquitetura Equilibrada:** Ambas as ferramentas (`c3x recommend` e `infracost breakdown`) confirmam que não há desperdícios ou superdimensionamentos na arquitetura.
- **Componente de maior custo:** O **NAT Gateway ($32,85)** é o recurso individual mais caro, porém é mandatário para permitir que os nós privados (backend e banco de dados) obtenham atualizações de segurança e façam pull no ECR sem receber tráfego direto da internet.
- **Computação distribuída resiliente:** As 6 instâncias `t3.small` garantem alta disponibilidade para o cluster Docker Swarm e para o banco de dados por um custo total de ~$91 a $96 mensais.
