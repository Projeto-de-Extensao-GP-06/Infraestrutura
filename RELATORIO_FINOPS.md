# Relatório de FinOps - Análise de Custos e Otimização

**Data:** 26/09/2026  
**Ferramenta:** Infracost v2.16.3  
**Projeto:** Infraestrutura SGPJ (Cloud AWS)

---

## Resumo Geral

### Visão Geral dos Custos
- **Total de Recursos:** 67 (30 com custos, 37 gratuitos)
- **Custo Mensal Estimado:** $310 USD
- **Custo Anual Estimado:** $3.720 USD
- **Economia Potencial Anual:** $1.971 USD (53% de redução)

### Status das Políticas
- **Políticas FinOps:** 20 (11 falhando)
- **Políticas de Tagging:** 1 (1 falhando)
- **Guardrails:** 0
- **Orçamentos:** 0
- **Diagnostics:** 2 avisos

---

## Análise de Custos por Recurso

### Top 10 Recursos Mais Caros

| Recurso | Quantidade | Custo Mensal | % do Total |
|---------|------------|--------------|------------|
| aws_db_instance.mysql | 1 | $161 | 52% |
| aws_nat_gateway.ngw | 1 | $33 | 11% |
| aws_instance.observability | 1 | $17 | 5% |
| aws_lb.app | 1 | $16 | 5% |
| aws_instance.app_a | 1 | $16 | 5% |
| aws_instance.db | 1 | $16 | 5% |
| aws_instance.backend_b | 1 | $16 | 5% |
| aws_instance.backend_a | 1 | $16 | 5% |
| aws_instance.app_b | 1 | $16 | 5% |
| aws_cloudwatch_dashboard.sgpj | 1 | $3 | 1% |

### Distribuição de Custos por Tipo de Serviço

- **RDS (Banco de Dados):** $161/mês (52%)
- **EC2 (Computação):** $97/mês (31%)
- **NAT Gateway:** $33/mês (11%)
- **Load Balancer:** $16/mês (5%)
- **CloudWatch:** $3/mês (1%)
- **Outros (gratuitos):** $0/mês (0%)

---

## Recomendações de Otimização de Custos

### 1. Oportunidades de Economia Significativas

### **Migração para Instâncias Graviton (EC2)**
**Impacto:** $210.24/ano de economia  
**Descrição:** Substituir instâncias EC2 t3.small por t4g.small (Graviton ARM)

- **Instâncias Afetadas:**
  - aws_instance.app_a: $35.04/ano
  - aws_instance.app_b: $35.04/ano
  - aws_instance.backend_a: $35.04/ano
  - aws_instance.backend_b: $35.04/ano
  - aws_instance.db: $35.04/ano
  - aws_instance.observability: $35.04/ano

**Benefícios Adicionais:**
- Redução de 168.8g CO2/mês por instância
- Economia de 2.5L de água/mês por instância

### **Atualização de Versão do RDS**
**Impacto:** $1.752/ano de economia  
**Descrição:** Atualizar versão do MySQL 8.0 para versão suportada

- **Recurso:** aws_db_instance.mysql
- **Ação:** Atualizar engine_version para versão atual suportada
- **Motivo:** Evitar custos de suporte estendido

### **Migração RDS para Graviton**
**Impacto:** $8.76/ano de economia  
**Descrição:** Substituir db.t3.micro por db.t4g.micro

- **Recurso:** aws_db_instance.mysql
- **Ação:** Mudar instance_class para Graviton

### 2. Melhorias de Segurança e Compliance

### **Habilitar SSL para S3**
**Recursos Afetados:** aws_s3_bucket.bronze, silver, gold  
**Ação:** Adicionar bucket policy negando requisições não-SSL  
**Benefício:** Proteção de dados em trânsito (Security Hub S3.5)

### **Remover IPs Públicos de Instâncias EC2**
**Recursos Afetados:** Todas as instâncias EC2 (6 instâncias)  
**Ação:** Desabilitar associate_public_ip_address  
**Benefício:** Redução de superfície de ataque (Security Hub EC2.9, EC2.25)

### **Habilitar CloudWatch Logs para RDS**
**Recurso:** aws_db_instance.mysql  
**Ação:** Exportar logs (audit, error, general, slowquery)  
**Benefício:** Monitoramento e auditoria (Security Hub RDS.9)


---

## Problemas de Tagging
### Status Atual
- **53 recursos** sem tags adequadas
- **Tags obrigatórias faltando:** Service, Environment
- **Formato esperado:**
  - `Service`: (obrigatório, qualquer valor)
  - `Environment`: (obrigatório, valores: Dev/Stage/Prod)

### Recursos Sem Tags Adequadas

**Principais grupos de recursos afetados:**
- Instâncias EC2 (app_a, app_b, backend_a, backend_b, db, observability)
- Subnets (9 subnets)
- S3 Buckets (bronze, silver, gold)
- Componentes VPC (VPC, Internet Gateway, NAT Gateway)
- Recursos Data Lake (Glue crawlers, databases, jobs)
- RDS e componentes relacionados

**Impacto:** Dificuldade em rastreamento de custos e alocação por centro de custo

---

## Diagnósticos e Avisos

### Warnings Detectados (2)
1. **Problemas de configuração** em recursos específicos

```Missing input variable: missing input variable — variables.tf:85-88
Missing input variable: missing input variable — variables.tf:116-120
Info: error calling function "file": file path C:\Users\lucas\Desktop\Coisas\codes\Projeto\Infraestrutura\scripts\util\bootstrap.sh is not within the repo root — ec2.tf:36
Info: error calling function "file": file path C:\Users\lucas\Desktop\Coisas\codes\Projeto\Infraestrutura\scripts\util\bootstrap.sh is not within the repo root — ec2.tf:48
Info: error calling function "file": file path C:\Users\lucas\Desktop\Coisas\codes\Projeto\Infraestrutura\scripts\util\bootstrap.sh is not within the repo root — ec2.tf:74
Info: error calling function "file": file path C:\Users\lucas\Desktop\Coisas\codes\Projeto\Infraestrutura\scripts\util\bootstrap.sh is not within the repo root — ec2.tf:10
Info: error calling function "file": file path C:\Users\lucas\Desktop\Coisas\codes\Projeto\Infraestrutura\scripts\util\bootstrap.sh is not within the repo root — ec2.tf:23
Info: error calling function "file": file path C:\Users\lucas\Desktop\Coisas\codes\Projeto\Infraestrutura\scripts\util\bootstrap.sh is not within the repo root — ec2.tf:60
```

---

## Plano de Ação Prioritário

### Imediato (Alto Impacto Financeiro)
1. Migrar instâncias EC2 para Graviton t4g.small
2. Atualizar versão do RDS MySQL
3. Migrar RDS para Graviton t4g.micro
4. Implementar lifecycle policies para S3

### Curto Prazo (Segurança e Compliance)
1. Habilitar SSL para buckets S3
2. Remover IPs públicos de instâncias EC2
3. Habilitar CloudWatch logs para RDS


### Médio Prazo (Governança)
1. Implementar tags obrigatórias (Service, Environment)
2. Configurar budget alerts no AWS Budgets
3. Estabelecer políticas de tag enforcement

---

## Conclusão

A infraestrutura atual apresenta um custo mensal de **$310 USD** com uma economia potencial de **$1.971 USD/ano (53%)** através das otimizações recomendadas. As principais oportunidades de economia estão na:

1. **Migração para processadores Graviton** (EC2 e RDS) - $219/ano
2. **Atualização de versão do RDS** - $1.752/ano

Além da economia financeira, as recomendações também proporcionam:
- Melhoria na segurança (SSL, remoção de IPs públicos)
- Compliance com AWS Security Hub
- Sustentabilidade ambiental (redução de CO2 e consumo de água)
- Melhor governança através de tagging consistente

---

## Próximos Passos

1. Priorizar implementação das recomendações de alto impacto financeiro
2. Estabelecer processo de revisão regular de custos (mensal)
3. Implementar automação de políticas de tagging
4. Documentar padrões de infraestrutura otimizados para futuros projetos