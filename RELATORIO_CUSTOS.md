# 💰 Relatório de Custos e FinOps — SGPJ Infraestrutura

Relatório técnico de estimativa e validação de custos de nuvem da infraestrutura provisionada via Terraform na AWS (`us-east-1`), gerado através das ferramentas **c3x** e **Infracost**.

---

## 1. Resumo Executivo

| Métrica | Valor Estimado |
|---|---|
| **Custo Total Projetado (Mensal contínuo)** | **$ 148,61 / mês** |
| **Custo por Hora da Infraestrutura** | **~$ 0,20 / hora** |
| **Custo para Laboratório de Testes (4 horas)** | **~$ 0,81** |
| **Limite do Voucher AWS Academy** | **$ 100,00 por lab** |
| **Status de Viabilidade Econômica** | **✅ 100% Viável e Seguro para uso acadêmico** |

> [!NOTE]
> No modelo de uso de laboratórios acadêmicos, a infraestrutura não fica ligada 24/7 o mês inteiro. Ao subir para testes e apresentações e executar `terraform destroy` em seguida, o consumo real contra o saldo do voucher é de centavos.

---

## 2. Detalhamento de Custos por Recurso (Extração c3x)

Valores obtidos diretamente das tabelas de preços oficiais da AWS para a região `us-east-1`:

### 🖥️ Computação & Instâncias EC2

| Recurso | Tipo | Quantidade / Horas | Preço Unitário | Subtotal Mensal |
|---|---|---|---|---|
| `aws_instance.app_a` | `t3.small` (Linux) | 730 horas | $ 0,0208 / hora | **$ 15,18** |
| `aws_instance.app_b` | `t3.small` (Linux) | 730 horas | $ 0,0208 / hora | **$ 15,18** |
| `aws_instance.backend_a` | `t3.small` (Linux) | 730 horas | $ 0,0208 / hora | **$ 15,18** |
| `aws_instance.backend_b` | `t3.small` (Linux) | 730 horas | $ 0,0208 / hora | **$ 15,18** |
| `aws_instance.db` | `t3.small` (Linux) | 730 horas | $ 0,0208 / hora | **$ 15,18** |
| `aws_instance.observability[0]` | `t3.small` (Linux) | 730 horas | $ 0,0208 / hora | **$ 15,18** |
| Volume EBS Observabilidade | `gp3` | 20 GB / mês | $ 0,0800 / GB | **$ 1,60** |
| **Subtotal Computação** | | | | **$ 92,70 / mês** |

---

### 🌐 Rede, Conectividade & Balanceamento

| Recurso | Descrição | Volume Base | Preço Unitário | Subtotal Mensal |
|---|---|---|---|---|
| `aws_nat_gateway.ngw` | NAT Gateway (subnets privadas) | 730 horas | $ 0,0450 / hora | **$ 32,85** |
| `aws_lb.app` | Application Load Balancer (ALB) | 730 horas | $ 0,0225 / hora | **$ 16,43** |
| `aws_eip.nat` | IP Público IPv4 para o NAT | 730 horas | $ 0,0050 / hora | **$ 3,65** |
| **Subtotal Rede** | | | | **$ 52,93 / mês** |

---

### 📊 Monitoramento, Armazenamento & Dados

| Recurso | Descrição | Base de Cálculo | Subtotal Mensal |
|---|---|---|---|
| `aws_cloudwatch_dashboard.sgpj` | Dashboard customizado | 1 dashboard | **$ 3,00** |
| `aws_ecr_repository` (Frontend & Backend) | Repositório de imagens Docker | Cobrado por GB armazenado ($0,10/GB) | **$ 0,00** *(base)* |
| `aws_efs_file_system.app_efs` | Armazenamento compartilhado NFS | Cobrado por GB armazenado ($0,16/GB) | **$ 0,00** *(base)* |
| `aws_s3_bucket` (Bronze, Silver, Gold, Athena) | Buckets Data Lake e Logs | Cobrado por GB armazenado ($0,023/GB) | **$ 0,00** *(base)* |
| `aws_athena_workgroup` & Named Queries | Consultas analíticas SQL | Cobrado por TB escaneado ($5,00/TB) | **$ 0,00** *(base)* |
| **Subtotal Dados & Monitoramento** | | | **$ 3,00 / mês** |

---

### 💵 Custo Total Projetado
$$\text{Total} = \$92,70 \text{ (EC2/EBS)} + \$52,93 \text{ (Rede/ALB/NAT)} + \$3,00 \text{ (CloudWatch)} = \mathbf{\$ 148,61 \text{ / mês}}$$

---

## 3. Validação de Coerência Técnica

1. **Preço da `t3.small` em us-east-1:**
   - 2 vCPUs e 2 GB de RAM custam exatamente `$0,0208` por hora na AWS. Em 730 horas (mês comercial), totaliza `$15,184`. O cálculo é exato.
2. **NAT Gateway:**
   - Custo fixo da AWS de `$0,045` por hora em que o gateway existe, totalizando `$32,85`. É o componente de rede isolada mais caro, mas obrigatório para que as instâncias privadas baixem atualizações e acessem o ECR sem expor suas portas à internet.
3. **Cobrança recente de IPv4 Público:**
   - Desde 01/02/2024, a AWS cobra `$0,005/hora` por cada endereço IPv4 público alocado (o Elastic IP do NAT Gateway gera `$3,65/mês`). A ferramenta capturou essa cobrança com precisão.
4. **Otimizações da Arquitetura:**
   - O comando `c3x recommend` analisou a infraestrutura e reportou: `c3x: no optimisations found`. Isso significa que os recursos já estão selecionados no menor tamanho viável para produção estável.

---

## 4. Como Executar as Ferramentas Novamente

Ambas as ferramentas estão instaladas no ambiente Windows:
- `c3x`: `C:\Program Files\c3x\c3x.exe`
- `infracost`: `C:\Program Files\infracost-master\infracost.exe`

### 4.1 Executar o c3x
O `c3x` roda sem necessidade de API key nem autenticação em nuvem:

```powershell
# Estimativa em formato de texto no terminal:
c3x estimate --path "infra\terraform" --allow-file-functions --cache-path "infra\.c3x-cache.sqlite"

# Estimativa formatada em Markdown:
c3x estimate --path "infra\terraform" --allow-file-functions --cache-path "infra\.c3x-cache.sqlite" --format markdown

# Verificar se existem recomendações de economia:
c3x recommend --path "infra\terraform" --cache-path "infra\.c3x-cache.sqlite"
```

### 4.2 Executar o Infracost
O Infracost requer login interativo prévio para renovar o token:

```powershell
# 1. Realizar login (abre o navegador para autenticar):
infracost auth login

# 2. Rodar a análise de custo e políticas:
infracost scan "infra\terraform"
```
