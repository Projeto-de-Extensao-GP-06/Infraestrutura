# Orçamento de Infraestrutura — SGPJ

> Região: `us-east-1` (N. Virginia) | Modelo de preço: On-Demand | Referência: AWS Pricing Calculator (mai/2026)

---

## 1. Inventário Provisionado

| Recurso                    | Configuração                                          | Qtd         |
| -------------------------- | ----------------------------------------------------- | ----------- |
| EC2 app-a / app-b          | t3.small, 2 vCPU, 2 GB RAM, 20 GB gp3, público        | 2           |
| EC2 backend-a / backend-b  | t3.small, 2 vCPU, 2 GB RAM, 8 GB gp3, privado         | 2           |
| EC2 ec2-db                 | t3.small, 2 vCPU, 2 GB RAM, 8 GB gp3, privado         | 1           |
| EC2 ec2-observability      | t3.small, 2 vCPU, 2 GB RAM, 20 GB gp3, público        | 1           |
| RDS MySQL 8.0              | db.t3.micro, 20 GB gp3, Single-AZ, backup 7 dias      | 1           |
| Application Load Balancer  | HTTP, 2 AZs                                           | 1           |
| NAT Gateway                | 1 EIP, subnet pública AZ-a                            | 1           |
| EFS                        | Standard (Bursting), 2 mount targets                  | 1           |
| SNS                        | 1 tópico, 1 subscriber e-mail                         | 1           |
| IPs públicos IPv4          | app-a, app-b, observability, NAT GW                   | 4           |
| EBS (raiz das EC2)         | gp3 — app/obs: 20 GB × 2; backend × 2 + db: 8 GB × 3  | 6 vol.      |
| API externa de IA          | Ex: OpenAI, Anthropic — chamada HTTP do backend EC2   | sob demanda |
| Lambda                     | 1 invocação/mês — reindexação da base de conhecimento | 1 fn        |
| OneDrive (Microsoft Graph) | Fonte dos documentos da base de conhecimento          | externo     |
| RDS pgvector               | Extensão vetorial no RDS existente (sem custo extra)  | —           |

---

## 2. Orçamento Detalhado — Cenário Atual (MVP)

> Base: 730 horas/mês (24×7). Preços On-Demand us-east-1.

### 2.1 Compute — EC2

| Instância         | h/mês | Preço/h | Subtotal   |
| ----------------- | ----- | ------- | ---------- |
| ec2-app-a         | 730   | $0,0208 | $15,18     |
| ec2-app-b         | 730   | $0,0208 | $15,18     |
| ec2-backend-a     | 730   | $0,0208 | $15,18     |
| ec2-backend-b     | 730   | $0,0208 | $15,18     |
| ec2-db            | 730   | $0,0208 | $15,18     |
| ec2-observability | 730   | $0,0208 | $15,18     |
| **Subtotal EC2**  |       |         | **$91,10** |

### 2.2 Armazenamento — EBS (gp3)

| Volume             | Tamanho | Preço/GB | Subtotal  |
| ------------------ | ------- | -------- | --------- |
| app-a raiz         | 20 GB   | $0,08    | $1,60     |
| app-b raiz         | 20 GB   | $0,08    | $1,60     |
| backend-a raiz     | 8 GB    | $0,08    | $0,64     |
| backend-b raiz     | 8 GB    | $0,08    | $0,64     |
| ec2-db raiz        | 8 GB    | $0,08    | $0,64     |
| observability raiz | 20 GB   | $0,08    | $1,60     |
| **Subtotal EBS**   |         |          | **$6,72** |

### 2.3 Banco de Dados — RDS MySQL

| Item                  | Detalhe                | Subtotal   |
| --------------------- | ---------------------- | ---------- |
| Instância db.t3.micro | 730h × $0,017/h        | $12,41     |
| Storage gp3 20 GB     | $0,115/GB/mês          | $2,30      |
| Backup (7 dias)       | 1× storage = free tier | $0,00      |
| **Subtotal RDS**      |                        | **$14,71** |

### 2.4 Rede

> **Sobre API calls e custo de rede:** O backend EC2 (subnet privada) acessa APIs externas (IA, etc.) obrigatoriamente pelo NAT Gateway — incorrendo em custo de processamento de dados. Para serviços **AWS** (ex: S3, DynamoDB), existem VPC Endpoints gratuitos que bypassam o NAT. Para APIs **externas** (OpenAI, OneDrive/Graph API), não existe VPC Endpoint — o tráfego sempre passa pelo NAT. Porém, a Lambda executa fora da VPC por padrão, então ela chama o OneDrive diretamente sem usar o NAT Gateway.

| Item                                      | Detalhe                                        | Subtotal   |
| ----------------------------------------- | ---------------------------------------------- | ---------- |
| NAT Gateway — fixo                        | 730h × $0,045/h                                | $32,85     |
| NAT Gateway — dados OS/Docker/updates     | ~4,5 GB × $0,045/GB                            | $0,20      |
| NAT Gateway — tráfego API de IA (backend) | ~500 req × ~10KB = 5 MB × $0,045/GB            | $0,01      |
| NAT Gateway — tráfego OneDrive (backend)  | ~500 consultas × ~50KB doc = 25 MB × $0,045/GB | $0,01      |
| ALB — fixo                                | 730h × $0,008/h                                | $5,84      |
| ALB — LCU (baixo tráfego)                 | ~0,5 LCU-h × 730h × $0,008                     | $2,92      |
| IPs públicos IPv4 (×4)                    | 4 × 730h × $0,005/h                            | $14,60     |
| Data transfer out (estimado)              | ~10 GB × $0,09/GB                              | $0,90      |
| **Subtotal Rede**                         |                                                | **$57,32** |

> **Conclusão sobre endpoints:** O backend EC2 (subnet privada) acessa tanto a API de IA quanto o OneDrive via NAT Gateway. O OneDrive também é chamado pela Lambda durante a reindexação mensal — nesse caso sem custo de NAT, pois a Lambda não está na VPC. O impacto real no custo de dados do NAT é **~$0,02/mês** — centavos, pois os payloads de API são pequenos. O custo dominante do NAT é a taxa fixa horária ($32,85), independente de volume.

### 2.5 Armazenamento — EFS

| Item                 | Detalhe      | Subtotal  |
| -------------------- | ------------ | --------- |
| EFS Standard (~5 GB) | $0,30/GB/mês | $1,50     |
| **Subtotal EFS**     |              | **$1,50** |

### 2.6 Notificações — SNS

| Item             | Detalhe              | Subtotal  |
| ---------------- | -------------------- | --------- |
| SNS e-mail       | Primeiros 1.000 free | $0,00     |
| **Subtotal SNS** |                      | **$0,00** |

### 2.7 Inteligência Artificial

> **Arquitetura:** O backend EC2 **não roda nenhum modelo de IA localmente**. Em cada requisição do usuário, ele faz chamadas HTTP para a **Microsoft Graph API (OneDrive)** para buscar documentos da base de conhecimento, e também para a **API externa de IA** para gerar a resposta. Ambas as chamadas saem pelo NAT Gateway (backend está em subnet privada). A Lambda executa **1 vez por mês**: também acessa o OneDrive para processar documentos novos, gera embeddings e atualiza o índice no RDS (pgvector) — nesse caso sem NAT, pois Lambda não está na VPC.

| Item                                       | Detalhe                                                        | Subtotal  |
| ------------------------------------------ | -------------------------------------------------------------- | --------- |
| API de IA — inferência (entrada)           | ~500 req/mês × 2.000 tok × $0,00015/1K tok _(ex: GPT-4o-mini)_ | $0,15     |
| API de IA — inferência (saída)             | ~500 req/mês × 500 tok × $0,00060/1K tok                       | $0,15     |
| API de IA — embeddings (update mensal)     | ~250K tokens × $0,00002/1K tok _(ex: text-embedding-3-small)_  | $0,01     |
| Lambda — reindexação (1×/mês, 1 GB, 5 min) | 1 inv × 300s × $0,0000167/GB-s                                 | $0,01     |
| OneDrive (Microsoft Graph API)             | Serviço Microsoft, sem custo AWS                               | $0,00     |
| RDS pgvector — vetores no RDS existente    | Sem custo adicional                                            | $0,00     |
| **Subtotal IA**                            |                                                                | **$0,32** |

> **Por que tão barato?** A API cobra por token consumido. O EC2 de backend não precisa de upgrade — ele só faz chamadas HTTP. Toda a computação pesada fica no provedor da API, fora da sua infraestrutura.

> **Comparativo de provedores (500 req/mês, mesmo volume):**
>
> | Provedor  | Modelo         | Custo/mês |
> | --------- | -------------- | --------- |
> | OpenAI    | GPT-4o-mini    | ~$0,33    |
> | Anthropic | Claude 3 Haiku | ~$0,44    |
> | Groq      | Llama 3.1 8B   | ~$0,05    |
> | OpenAI    | GPT-4o         | ~$5,00    |
>
> Para base de conhecimento com baixo volume, **GPT-4o-mini ou Groq** são suficientes e mais baratos.

---

### Resumo Mensal — Cenário MVP

| Grupo                           | Custo         |
| ------------------------------- | ------------- |
| EC2 Compute                     | $91,10        |
| EBS Storage                     | $6,72         |
| RDS MySQL                       | $14,71        |
| Rede (NAT, ALB, IPv4, transfer) | $57,34        |
| EFS                             | $1,50         |
| SNS                             | $0,00         |
| **IA (API externa + Lambda)**   | **$0,32**     |
| **TOTAL MENSAL**                | **$171,68**   |
| **TOTAL ANUAL**                 | **$2.060,16** |

> **Atenção:** O NAT Gateway ($32,85/mês) representa **19%** do custo total — e isso é a **taxa fixa**, não o tráfego. Adicionar chamadas de API externas aumenta o custo de dados do NAT em centavos, não em dólares. O OneDrive (Microsoft Graph) tem **$0 de custo AWS**.

---

## 3. Cenários de Crescimento

### 3.1 Cenário Atual — MVP (mês 1–2)

Infraestrutura como está. 6 EC2 t3.small, tráfego baixo, sem redundância de banco.

**Custo:** ~$172/mês

#### Capacidade e Limite de Usuários

> O **gargalo principal** neste cenário é o RDS db.t3.micro (1 GB RAM), que suporta até ~66 conexões simultâneas ao banco. O backend usa pool de conexões (HikariCP), consumindo ~20 dessas conexões.

| Métrica                           | Valor estimado   | Explicação                                  |
| --------------------------------- | ---------------- | ------------------------------------------- |
| Requisições/segundo (pico)        | ~80–100 req/s    | 2× backend t3.small com Tomcat 200 threads  |
| Usuários simultâneos ativos       | ~150–300         | Usuários fazendo requisições ao mesmo tempo |
| Usuários navegando (frontend)     | ~2.000–4.000     | Nginx serve estáticos com custo mínimo      |
| Usuários cadastrados              | ilimitado        | Não impacta performance                     |
| Pico suportável antes de degradar | ~500 simultâneos | Acima disso: filas, timeout, erros 503      |
| Conexões DB disponíveis           | ~46 livres de 66 | Restante é consumido pelos backends         |

**O que acontece ao atingir o limite:** O ALB recebe os requests, mas o backend fica com threads ocupadas esperando o banco. Usuários começam a ver telas lentas e depois erros 503 (service unavailable).

---

### 3.2 Cenário Crescimento — Adoção Inicial (mês 3–6)

Hipótese: projeto aprovado, primeiros usuários reais, tráfego cresce 3×.

| Mudança                               | Motivo                       |
| ------------------------------------- | ---------------------------- |
| EC2 app-a/b: t3.small → t3.medium     | Mais carga no frontend       |
| RDS: db.t3.micro → db.t3.small, 40 GB | Mais conexões e dados        |
| ALB LCU: 0,5 → 2 LCU                  | Mais tráfego HTTP            |
| Data transfer out: 10 GB → 50 GB      | Mais usuários acessando      |
| EFS: 5 GB → 20 GB                     | Upload de arquivos crescente |

| Grupo                             | Custo Estimado |
| --------------------------------- | -------------- |
| EC2 (2× t3.medium + 4× t3.small)  | $123,94        |
| EBS                               | $6,72          |
| RDS db.t3.small + 40 GB           | $38,86         |
| Rede (ALB, NAT, IPv4, transfer)   | $61,90         |
| EFS 20 GB                         | $6,00          |
| IA (API externa ~2K req + Lambda) | $1,50          |
| **TOTAL**                         | **~$239/mês**  |

#### Capacidade e Limite de Usuários

> Gargalo migra para o backend (ainda t3.small) e o RDS db.t3.small (2 GB RAM, ~150 conexões). O frontend melhorou com t3.medium mas o backend não escalou.

| Métrica                           | Valor estimado     | Explicação                                     |
| --------------------------------- | ------------------ | ---------------------------------------------- |
| Requisições/segundo (pico)        | ~100–150 req/s     | Backend ainda t3.small ×2, mas RDS mais fôlego |
| Usuários simultâneos ativos       | ~400–700           | RDS com mais conexões disponíveis              |
| Usuários navegando (frontend)     | ~8.000–12.000      | 2× t3.medium no Nginx                          |
| Pico suportável antes de degradar | ~1.000 simultâneos |                                                |
| Conexões DB disponíveis           | ~110 livres de 150 |                                                |

---

### 3.3 Cenário Escala — Produção (mês 7–12)

Hipótese: produto consolidado, SLA exigido, alta disponibilidade necessária.

| Mudança                                      | Motivo                             |
| -------------------------------------------- | ---------------------------------- |
| RDS: Single-AZ → Multi-AZ                    | Eliminação de SPOF no banco        |
| EC2 backend: 2 → 4 instâncias (Auto Scaling) | Escala horizontal                  |
| EC2 app: t3.medium → t3.large                | Suporte a pico de acessos          |
| RDS: db.t3.small → db.t3.medium, 100 GB      | Volume de dados crescente          |
| CloudFront (CDN)                             | Reduz latência e custo de transfer |
| ElastiCache Redis (cache.t3.micro)           | Reduz carga no RDS                 |
| Data transfer: 50 GB → 200 GB                | Base de usuários maior             |

| Grupo                                                        | Custo Estimado |
| ------------------------------------------------------------ | -------------- |
| EC2 (2× t3.large app + 4× t3.small backend + 1× obs + 1× db) | $218,40        |
| EBS                                                          | $14,40         |
| RDS Multi-AZ db.t3.medium + 100 GB                           | $144,65        |
| ElastiCache cache.t3.micro                                   | $24,82         |
| CloudFront (~200 GB/mês)                                     | $17,40         |
| Rede (NAT, ALB × 2, IPv4, transfer reduzido)                 | $65,00         |
| EFS 50 GB                                                    | $15,00         |
| IA (API externa ~10K req + Lambda + S3)                      | $6,50          |
| **TOTAL**                                                    | **~$506/mês**  |

#### Capacidade e Limite de Usuários

> Neste cenário, o ElastiCache Redis absorve ~60% das queries ao banco. O gargalo se desloca para o backend (agora 4 instâncias). O RDS Multi-AZ garante failover automático em ~60 segundos.

| Métrica                           | Valor estimado     | Explicação                        |
| --------------------------------- | ------------------ | --------------------------------- |
| Requisições/segundo (pico)        | ~300–600 req/s     | 4× backend t3.small + Redis cache |
| Usuários simultâneos ativos       | ~800–2.000         | Redis reduz pressão no banco 60%  |
| Usuários navegando (frontend)     | ~20.000–40.000     | 2× t3.large + CloudFront          |
| Pico suportável antes de degradar | ~3.000 simultâneos | Com Auto Scaling configurado      |
| Conexões DB efetivas usadas       | ~80 de 300         | Redis intercepta o restante       |
| SLA estimado                      | 99,5%              | RDS Multi-AZ + 2 AZs de app       |

> **Alerta de escala para IA:** Se o volume crescer e exigir um modelo mais capaz (GPT-4o ou Claude Sonnet), o custo de inferência pode saltar para ~$100+/mês. Recomenda-se manter GPT-4o-mini ou Groq enquanto a qualidade for suficiente.

---

### 3.4 Tabela Comparativa de Capacidade por Cenário

| Métrica                       | MVP             | Crescimento      | Escala                   |
| ----------------------------- | --------------- | ---------------- | ------------------------ |
| Usuários simultâneos ativos   | ~300            | ~700             | ~2.000                   |
| Pico antes de degradar        | 500             | 1.000            | 3.000                    |
| Usuários navegando (estático) | 4.000           | 12.000           | 40.000                   |
| Requisições/segundo (pico)    | 100 req/s       | 150 req/s        | 600 req/s                |
| Gargalo principal             | RDS db.t3.micro | Backend t3.small | Auto Scaling configurado |
| Failover de banco             | Nenhum (SPOF)   | Nenhum (SPOF)    | Automático (~60s)        |
| Custo por usuário ativo/mês   | ~$0,57          | ~$0,34           | ~$0,26                   |

> **Como ler:** "usuários simultâneos ativos" são os que estão clicando e esperando resposta no mesmo momento. A mesma infraestrutura pode ter **milhares de usuários cadastrados** sem impacto — o que importa é quantos acessam ao mesmo tempo.

---

### 3.5 Planos de Preço AWS

A AWS oferece 5 modelos de preço para EC2. Escolher o certo pode reduzir **até 56% do custo de compute**.

#### Comparativo dos Planos

| Plano                              | Desconto vs On-Demand | Compromisso                  | Flexibilidade                  | Ideal para                            |
| ---------------------------------- | --------------------- | ---------------------------- | ------------------------------ | ------------------------------------- |
| **On-Demand**                      | 0% (base)             | Nenhum                       | Total                          | Desenvolvimento, spikes imprevisíveis |
| **Savings Plans — Compute**        | ~20%                  | 1 ou 3 anos (valor/hora)     | Alta — qualquer família/região | Workloads que mudam de tipo           |
| **Savings Plans — EC2**            | ~30%                  | 1 ou 3 anos (família fixada) | Média — família t3 fixada      | Backend estável, mesmo tipo           |
| **Reserved Instances (RI) 1 ano**  | ~36–39%               | 1 ano                        | Baixa — tipo+AZ fixados        | App/backend sem previsão de mudar     |
| **Reserved Instances (RI) 3 anos** | ~54–56%               | 3 anos                       | Muito baixa                    | Produção madura e estável             |
| **Spot Instances**                 | ~70–90%               | Nenhum                       | Total, mas interrompível       | Observability, jobs, IA batch         |

#### Custo EC2 por Plano — MVP (6× t3.small, 730h)

| Plano                           | Preço/h por instância | Total 6 instâncias/mês | Economia                   |
| ------------------------------- | --------------------- | ---------------------- | -------------------------- |
| On-Demand                       | $0,0208               | $91,10                 | —                          |
| Savings Plans Compute           | $0,0166               | $72,77                 | -$18,33                    |
| Savings Plans EC2               | $0,0146               | $63,94                 | -$27,16                    |
| RI 1 ano (No Upfront)           | $0,0133               | $58,27                 | -$32,83                    |
| RI 1 ano (All Upfront)          | $0,0126               | $55,25                 | -$35,85 (+ $663 upfront)   |
| RI 3 anos (All Upfront)         | $0,0092               | $40,30                 | -$50,80 (+ $1.450 upfront) |
| Spot (obs + jobs, 2 instâncias) | ~$0,006               | _-$22 nos 2 Spot_      | Híbrido recomendado        |

> **Recomendação para produção:** RI 1 ano (No Upfront) para as instâncias de app e backend (sempre ligadas) + Spot para observability (não crítico). Isso gera **-$55/mês** vs On-Demand puro, sem desembolso antecipado.

#### Custo Total com Plano Híbrido Recomendado (MVP)

| Grupo                           | On-Demand   | Com Plano Híbrido   |
| ------------------------------- | ----------- | ------------------- |
| EC2 app + backend (4× RI 1 ano) | $60,74      | $39,80              |
| EC2 db + obs (2× Spot)          | $30,36      | $8,76               |
| Restante (rede, RDS, EFS, IA)   | $80,22      | $80,22              |
| **TOTAL**                       | **$171,96** | **~$128,78**        |
| **Economia**                    | —           | **-$43/mês (-25%)** |

> **Obs. sobre Spot para db/observability:** A EC2 de banco (ec2-db) não deve usar Spot pois pode ser interrompida. O uso de Spot é recomendado apenas para `ec2-observability`. Para ec2-db, usar On-Demand ou RI. (usuários simultâneos e custo)

```
Custo (USD/mês)          Usuários simultâneos
  511 |                       ● Escala           3.000 |
      |               · · ·                          |   · · ·
  240 |         ● Crescimento                 1.000 | ●
      |   · · ·                                     | · · ·
  172 | ● MVP                                    500 | ●
      +------------------------------->            +--->
         Mês  1–2  3–6  7–12                     Mês  1  3  7
```

      |                              ·  ·  ·

240 | ● Crescimento (c/ IA)
| · · ·
172 | ● MVP (c/ IA)
|
+-------------------------------------------> Mês
1 2 3 4 5 6 7 8 12

Custo incremental da IA por fase:
MVP: +$0,59/mês | Crescimento: +$2,50/mês | Escala: +$11,50/mês

```

---

## 4. Orçado × Realizado (AWS Academy)

> Para consultar o custo realizado: **AWS Console → Billing → Cost Explorer** ou **Vocareum → Account → Credit Usage**

### Referência de Custo por Sprint

Assumindo que a infraestrutura foi provisionada e destruída ao longo das sprints (não rodou 24×7 o mês inteiro):

| Período                    | Horas estimadas ligado | Custo estimado (proporcional) |
| -------------------------- | ---------------------- | ----------------------------- |
| Sprint 1 (setup inicial)   | ~40h                   | $9,38                         |
| Sprint 2 (backend + RDS)   | ~80h                   | $18,76                        |
| Sprint 3 (observabilidade) | ~120h                  | $28,14                        |
| Sprint 4 (refinamento)     | ~168h (1 semana)       | $39,40                        |
| **Total estimado**         |                        | **~$96**                      |

### Como interpretar o desvio

| Situação           | Causa Provável                                                              |
| ------------------ | --------------------------------------------------------------------------- |
| Realizado > Orçado | NAT Gateway ligado mesmo sem EC2 ligadas; EIPs soltos; snapshots esquecidos |
| Realizado ≈ Orçado | Infraestrutura destruída entre sprints, sem recursos órfãos                 |
| Realizado < Orçado | Infraestrutura ficou menos tempo ligada do que estimado                     |

> **Dica de auditoria:** No Cost Explorer, filtrar por recurso `aws_nat_gateway` — ele é cobrado 24×7 independente de ter tráfego, sendo o maior "vazamento" quando esquecido ligado.

---

## 5. Painel OpEx — Custos Operacionais em Nuvem

### Breakdown por Categoria (MVP)

```

EC2 Compute ████████████████████████████░ 53% ($91)
Rede / NAT █████████████████░░░░░░░░░░░░ 33% ($57)
RDS MySQL █████████░░░░░░░░░░░░░░░░░░░░ 9% ($15)
EBS Storage ████░░░░░░░░░░░░░░░░░░░░░░░░░ 4% ($7)
EFS █░░░░░░░░░░░░░░░░░░░░░░░░░░░░ 1% ($1)
IA (API ext.) ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ <1% ($0,33)

```

### Oportunidades de Otimização

| Ação                                         | Economia estimada          | Complexidade |
| -------------------------------------------- | -------------------------- | ------------ |
| Desligar NAT Gateway fora do horário         | -$22/mês                   | Baixa        |
| Reserved Instances 1 ano (EC2)               | -40% no compute = -$36/mês | Baixa        |
| Migrar EC2 db para RDS gerenciado (já feito) | Já otimizado               | —            |
| Savings Plans (Compute)                      | -20% geral                 | Baixa        |
| Remover IPs públicos desnecessários          | -$7/mês                    | Baixa        |
| **Potencial total de economia**              | **-$65/mês (~38%)**        |              |

### Custo por Camada da Aplicação

| Camada                     | Recursos                        | Custo    |
| -------------------------- | ------------------------------- | -------- |
| Frontend (app)             | 2× EC2 + ALB + 2× IPv4          | $47      |
| Backend                    | 2× EC2                          | $30      |
| Banco de Dados             | 1× EC2 + RDS + pgvector         | $27      |
| Rede / Conectividade       | NAT GW + transfer               | $34      |
| Observabilidade            | 1× EC2 + SNS                    | $16      |
| Storage                    | EBS + EFS + S3                  | $8       |
| **IA / Base Conhecimento** | **API externa + Lambda + S3**   | **<$1**  |
| **Total**                  |                                 | **$163** |

---

## 6. Pitch — Comitê Executivo (3 minutos)

---

**"Investimento em Infraestrutura: Do Código à Nuvem com Controle e Visibilidade"**

_Tempo estimado de leitura em voz alta: 2'50"_

---

Bom dia a todos.

Quero compartilhar com vocês o estado atual da nossa infraestrutura na nuvem, quanto estamos gastando e por que cada real investido está justificado.

**O que construímos**

Em poucas semanas, entregamos uma infraestrutura completa na AWS: duas instâncias de frontend com balanceamento de carga, dois servidores de backend, banco de dados gerenciado com backup automático, sistema de arquivos distribuído e uma camada completa de observabilidade — com monitoramento de métricas, logs centralizados, dashboards em tempo real e alertas automáticos por e-mail.

Tudo isso foi provisionado como código. Isso significa que podemos recriar toda a infraestrutura do zero em menos de dez minutos, e que cada mudança passa por revisão, versionamento e rastreabilidade.

**O que estamos gastando**

No cenário atual de desenvolvimento, o custo estimado é de **$171 por mês** em preços sob demanda. Em uma sprint típica de duas semanas, isso representa aproximadamente **$40 a $50**.

O maior custo isolado — o NAT Gateway, responsável por $33 dos $171 — é necessário para que nossos servidores de backend, que ficam em rede privada por segurança, possam acessar serviços externos sem exposição direta à internet. É um custo de segurança, não de desperdício.

**Qual é o caminho de crescimento**

Mapeamos três cenários: o atual de desenvolvimento, um cenário de adoção inicial em torno de $237 por mês, e um cenário de escala plena em produção em torno de $500 por mês. Esse crescimento é acompanhado de melhorias como alta disponibilidade no banco de dados, auto scaling no backend e entrega via CDN.

Identificamos também oportunidades de redução de custo de até 38% com Reserved Instances e otimização de recursos ociosos — o que levaria o custo de produção madura de $500 para aproximadamente $310 por mês.

**Nossa aposta em inteligência artificial**

Integramos IA à nossa plataforma com custo inicial de menos de **cinquenta centavos de dólar por mês**. O backend simplesmente faz chamadas HTTP para uma API externa de IA — não rodamos nenhum modelo localmente, não precisamos de servidores maiores. Uma Lambda executa uma vez ao mês para manter a base de conhecimento atualizada. Com o crescimento do projeto, esse custo escala proporcionalmente ao uso, sem surpresas.

**Por que isso importa**

Temos visibilidade total do que está sendo gasto e por quê. Temos alertas que disparam antes de problemas acontecerem. Temos dashboards que mostram saúde de CPU, memória, disco e banco em tempo real. E temos capacidade de auditar qualquer mudança feita na infraestrutura.

Não estamos operando no escuro. Estamos operando com controle.

Obrigado.

---

> **Nota de uso na apresentação:** Abrir o Grafana ao vivo na tela durante o pitch reforça a credibilidade. Mostrar um alerta real recebido no e-mail durante a demo é o argumento mais forte.

---

_Documento gerado em: maio/2026 | Infraestrutura: Grupo 06 — SGPJ | Escola: SPTech_
```
