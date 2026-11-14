# Relatório de Análise Exploratória de Dados (EDA) & Data Lakehouse

## 🎯 Pergunta de Negócio (Problem Statement)
> **"Como a taxa de inadimplência de Pessoa Física (PF) e Pessoa Jurídica (PJ) no Brasil se reflete no perfil da carteira de processos da beneficiária no volume de casos?"**

---

## 🏛️ 1. Arquitetura da Solução (Data Lakehouse Medalhão)

A solução foi estruturada no modelo **Medalhão (Bronze ➔ Silver ➔ Gold)** integrada com Amazon Athena e provisionamento automatizado de dashboards no Grafana:

```
[Fontes Externas]
  - BACEN SGS (APIs Públicas de Inadimplência, Selic e IPCA)
  - Processos da Carteira da Beneficiária (56 processos reais seed + histórico 2022-2026)
         │
         ▼
[Camada BRONZE (Raw S3)]
  - s3://sgpj-bronze-<ACCOUNT>/raw_data/bacen_sgs/
  - s3://sgpj-bronze-<ACCOUNT>/processos_beneficiaria/processos_carteira.csv
         │
         ▼ (ETL PyArrow / Pandas / Parquet Snappy)
[Camada SILVER (Curated S3)]
  - s3://sgpj-silver-<ACCOUNT>/bacen_indicadores/dados.parquet
  - s3://sgpj-silver-<ACCOUNT>/processos_carteira/dados.parquet
         │
         ▼ (Agregação Temporal Mensal, Métricas de Ticket Médio e Taxas)
[Camada GOLD (Analytical S3)]
  - s3://sgpj-gold-<ACCOUNT>/carteira_inadimplencia_analytics/dados.parquet
         │
         ▼ (Catálogo AWS Glue & AWS Athena)
[Tabela Athena: sgpj_gold.carteira_inadimplencia_analytics]
         │
         ▼ (Grafana Athena Datasource)
[Dashboard Executivo no Grafana: "Analise de Inadimplencia PF/PJ vs Carteira"]
```

---

## 📊 2. Evidências dos Painéis do Dashboard

### Painel 1: Indicadores Macroeconômicos e Operacionais (KPIs de Topo)
* **Taxa de Inadimplência PF (Atual):** `5.43%` (Pico histórico nacional)
* **Taxa de Inadimplência PJ (Atual):** `3.18%`
* **Taxa Selic a.a. (Atual):** `14.3%` (Juros restritivos no mercado de crédito)
* **% Processos com Penhora / Bloqueio:** `47.4%` (Quase metade da carteira em fase de execução forçada)

### Painel 2: Curva de Correlação de Pessoa Física (PF)
* **Comportamento Observado:**
  - Até 2024, a inadimplência PF manteve-se na faixa de 3,6% a 3,8%, com entrada média de 10 a 14 processos/mês na beneficiária.
  - Com o aumento expressivo da inadimplência PF para mais de 5,4% entre 2025 e 2026, o volume de novos processos PF subiu para **30 casos/mês**.
  - **Correlação positiva direta:** O aumento da inadimplência das famílias gera reflexo quase imediato no volume de ações de cobrança de contratos bancários, cartões de crédito e financiamentos.

### Painel 3: Curva de Correlação de Pessoa Jurídica (PJ)
* **Comportamento Observado:**
  - A taxa de inadimplência PJ oscila entre 2,1% e 3,2%.
  - O volume de processos PJ apresentou picos mais voláteis (8 a 15 casos/mês), fortemente correlacionados com o aperto monetário (Selic).

### Painel 4: Curva da Selic x Ticket Médio das Causas (R$)
* **Ticket Médio PF:** Estável em torno de **R$ 40,3k a R$ 46,1k**.
* **Ticket Médio PJ:** Médias elevadas de **R$ 234k a R$ 255k**, com causas ultrapassando R$ 400k em momentos de estresse de liquidez das empresas.
* **Impacto da Selic:** Quando a taxa Selic saltou de 10% para 14,3%, o custo financeiro das dívidas empresariais explodiu, aumentando tanto o ticket cobrado quanto a necessidade de judicialização de dívidas maiores.

### Painel 5: Perfil das Ações — Penhora Dura (SISBAJUD/SNIPER) vs Acordos
* **Penhoras e Bloqueios Forçados:** Representam **47.4%** dos processos em andamento. Ferramentas como SISBAJUD (bloqueio bancário), RENAJUD (veículos) e SNIPER/CNIB (busca patrimonial de imóveis e empresas) dominam a carteira.
* **Taxa de Acordos:** Permanece em torno de **10.5% a 13.2%**.
* **Diagnóstico Jurídico:** A baixa liquidez dos devedores dificulta a conciliação espontânea, forçando o escritório a avançar rapidamente para atos de expropriação patrimonial.

---

## 💡 3. Resposta à Pergunta de Negócio & Recomendações Estratégicas

### Conclusão Analítica
> O aumento da taxa de inadimplência no Brasil reflete-se de maneira assimétrica na carteira da beneficiária:
> 1. **Em Pessoa Física (PF):** O reflexo se dá prioritariamente por **VOLUME MASSIVO**. A elevação da inadimplência nacional multiplica os casos distribuídos (+120% no período analisado).
> 2. **Em Pessoa Jurídica (PJ):** O reflexo se dá por **VALOR E COMPLEXIDADE**. Embora o volume seja menor, o ticket médio é 6x superior (R$ 250k+), exigindo perícia patrimonial complexa.

---

### Recomendações para a Beneficiária

#### 1. Estratégia Comercial & Marketing Humanizado para Casos PF
* **Contexto:** Casos PF envolvem crédito consignado, financiamento de veículos e dívidas que afetam o sustento familiar e parentes.
* **Ação:** Adequar a abordagem de comunicação e atendimento para um modelo consultivo e de conciliação. 
* **Benefício:** Estimular acordos e composições extrajudiciais logo no início do processo (Fase Inicial/Citação), reduzindo o custo operacional de tramitar execuções infrutíferas que congestionam o judiciário.

#### 2. Núcleo Especializado de Investigação Patrimonial para Casos PJ
* **Contexto:** Com a Selic alta, empresas devedoras tendem a ocultar patrimônio ou transferir bens antes de sofrerem execução.
* **Ação:** Padronizar o acionamento em lote das ferramentas de constrição (SISBAJUD, RENAJUD e pedidos de instauração de Incidente de Desconsideração da Personalidade Jurídica - IDPJ) para atingir os sócios.
* **Benefício:** Maximização do índice de recuperação das causas de alto ticket (> R$ 200k).

#### 3. Inteligência Jurídica Preditiva
* **Ação:** Utilizar a base histórica de casos transitados em julgado para mapear quais varas e juízos concedem arrestos e pesquisas patrimoniais mais rapidamente, ajustando a petição inicial para obter tutelas de urgência cautelares antes da citação do devedor.

---

## 🛠️ 4. Como Reproduzir o Pipeline

Todo o pipeline é automatizado e pode ser replicado em qualquer conta AWS por meio do Terraform e do script dedicado:

```bash
# 1. Execucao via Terraform (provisiona Buckets, Glue, Athena e roda o pipeline)
cd terraform
terraform apply -auto-approve

# 2. Ou execucao manual do pipeline em Python
python scripts/datalake/pipeline_medalhao.py
```
