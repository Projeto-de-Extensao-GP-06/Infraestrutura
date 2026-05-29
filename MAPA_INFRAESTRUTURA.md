# Mapa da Infraestrutura — O que roda em cada máquina

## ec2-app-a e ec2-app-b

_Grupo `[app]` — instâncias públicas atrás do ALB_

**Instalado no sistema:**

- Docker Engine

**Containers rodando:**

| Container       | Imagem                             | Porta | Função                                      |
| --------------- | ---------------------------------- | ----- | ------------------------------------------- |
| `sgpj-frontend` | `lpamorim/sgpj-frontend`           | 3000  | App React / frontend                        |
| `nginx`         | `nginx:stable-alpine`              | 80    | Proxy reverso + serve HTML estático via EFS |
| `node-exporter` | `quay.io/prometheus/node-exporter` | 9100  | Métricas de CPU / memória / disco           |
| `alloy`         | `grafana/alloy`                    | —     | Coleta logs Docker → Loki central           |

---

## ec2-observability

_Grupo `[observability]` — instância dedicada em AZ us-east-1c_

**Instalado no sistema:**

- Docker Engine

**Containers rodando:**

| Container             | Imagem                             | Porta | Função                                                |
| --------------------- | ---------------------------------- | ----- | ----------------------------------------------------- |
| `prometheus`          | `prom/prometheus`                  | 9090  | Coleta métricas de todos os hosts                     |
| `loki`                | `grafana/loki`                     | 3100  | Armazena logs recebidos pelo Alloy                    |
| `alertmanager`        | `prom/alertmanager`                | 9093  | Roteamento de alertas (em migração para Grafana SMTP) |
| `cloudwatch-exporter` | `prom/cloudwatch-exporter`         | 9106  | Puxa métricas AWS (ALB, RDS, EFS)                     |
| `grafana`             | `grafana/grafana`                  | 3001  | Visualização + alertas por e-mail (SMTP)              |
| `node-exporter`       | `quay.io/prometheus/node-exporter` | 9100  | Métricas do próprio host de observabilidade           |
| `alloy`               | `grafana/alloy`                    | —     | Coleta logs locais dos containers acima               |

---

## ec2-backend-a e ec2-backend-b

_Grupo `[backend]` — instâncias privadas (acesso via ProxyJump por ec2-app-a)_

**Instalado no sistema:**

- Docker Engine

**Containers rodando:**

| Container       | Imagem                             | Porta | Função                    |
| --------------- | ---------------------------------- | ----- | ------------------------- |
| `node-exporter` | `quay.io/prometheus/node-exporter` | 9100  | Métricas de host          |
| `alloy`         | `grafana/alloy`                    | —     | Coleta logs Docker → Loki |

> Não há playbook definindo o container do backend ainda — só monitoramento.

---

## ec2-db

_Grupo `[db]` — instância privada_

**Instalado no sistema:**

- Docker Engine

**Containers rodando:**

| Container       | Imagem                             | Porta | Função             |
| --------------- | ---------------------------------- | ----- | ------------------ |
| `node-exporter` | `quay.io/prometheus/node-exporter` | 9100  | Métricas de host   |
| `alloy`         | `grafana/alloy`                    | —     | Coleta logs → Loki |

> O banco real é **RDS** (gerenciado pela AWS), não roda nesta EC2.

---

## Fluxo geral de dados

```
ec2-app-a/b        → node-exporter  ─┐
ec2-backend-a/b    → node-exporter  ─┼─→ Prometheus (observability) → Grafana
ec2-observability  → node-exporter  ─┘

ec2-app-a/b        → alloy ─┐
ec2-backend-a/b    → alloy ─┼─→ Loki (observability) → Grafana
ec2-observability  → alloy ─┘

CloudWatch (AWS)   ──────────→ cloudwatch-exporter → Prometheus → Grafana
```
