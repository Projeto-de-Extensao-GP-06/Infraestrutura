# Relatório de Teste de Carga - SGPJ (Apache JMeter)

## 1. Visão Geral da Arquitetura do Teste
- **Alvo do Teste**: Application Load Balancer (ALB) Público da AWS
- **URL**: `http://alb-app-1198994688.us-east-1.elb.amazonaws.com`
- **Ambiente de Destino**: Clusters Nginx (Web) balanceando para instâncias Spring Boot situadas em **Subnets Privadas** (`10.0.3.254` e `10.0.4.253`).
- **Autenticação**: Sessão baseada em Cookie seguro `authToken` (JWT) obtido via `/auth/login`.

---

## 2. Endpoints Avaliados
1. **`GET /dashboard`**: Consulta aos indicadores analíticos e KPIs de processos judiciais.
2. **`GET /processos?page=0&size=10`**: Listagem paginada de processos judiciais ativos e finalizados.
3. **`GET /processos/1`**: Detalhes e metadados completos de um processo específico.

---

## 3. Configuração do Cenário de Carga
- **Número de Usuários Concorrentes (Threads)**: 15 usuários virtuais
- **Loops por Usuário**: 10 repetições
- **Total de Amostras por Endpoint**: 150 requisições
- **Volume Total de Requisições**: 450 requisições

---

## 4. Tabela de Resultados - Aggregate Report

| Sampler Label | # Samples | Average (ms) | Median (ms) | 90% Line (ms) | 95% Line (ms) | 99% Line (ms) | Min (ms) | Max (ms) | Error % | Throughput | Received KB/s | Sent KB/s |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| **GET - /dashboard** | 150 | 220,07 | 211,00 | 265,00 | 315,00 | 422,00 | 171 | 457 | **0,00%** | 1,66/s | 1,25 | 0,19 |
| **GET - /processos** | 150 | 211,31 | 196,00 | 255,00 | 291,00 | 407,00 | 164 | 887 | **0,00%** | 1,66/s | 4,67 | 0,21 |
| **GET - /processos/1** | 150 | 168,73 | 157,00 | 201,00 | 217,00 | 266,00 | 143 | 689 | **0,00%** | 1,66/s | 1,26 | 0,20 |
| **TOTAL** | **450** | **200,04** | **192,00** | **247,00** | **280,00** | **422,00** | **143** | **887** | **0,00%** | **4,97/s** | **7,17** | **0,61** |

---

## 5. Análise de Desempenho e Conclusão
- **Taxa de Erro de 0%**: Todas as 450 requisições foram atendidas com sucesso (`HTTP 200 OK`), comprovando a estabilidade da infraestrutura e dos balanceadores.
- **Latência Média Global**: 200,04 ms, com 90% das requisições respondidas abaixo de 247 ms (ótima experiência de uso para sistemas judiciais em nuvem).
- **Consistência de Resposta**: O endpoint individual `GET /processos/1` apresentou o melhor tempo de resposta médio (168,73 ms).
- **Arquitetura de Segurança Validada**: O teste comprovou que o Load Balancer e o Nginx encaminham perfeitamente as requisições autenticadas para as instâncias da rede privada sem necessidade de expor o Backend diretamente à internet.
