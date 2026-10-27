# 🗺️ Mapa da Infraestrutura — SGPJ (Grupo 06)

Este documento descreve detalhadamente o que roda em cada instância EC2, como os serviços se comunicam, a topologia de rede e os componentes gerenciados na AWS.

---

## 🏗️ Topologia Geral

```
                                      INTERNET
                                         │
                                         ▼
                           ┌───────────────────────────┐
                           │   Application Load        │
                           │   Balancer (ALB :80)      │
                           └─────────────┬─────────────┘
                                         │
                 ┌───────────────────────┴───────────────────────┐
                 ▼ (Round-Robin HTTP :80)                        ▼
     ┌───────────────────────┐                       ┌───────────────────────┐
     │      ec2-app-a        │                       │      ec2-app-b        │
     │  (Subnet Pública A)   │                       │  (Subnet Pública B)   │
     │  ★ SWARM MANAGER ★    │                       │  ✦ SWARM WORKER ✦     │
     │  Serviço: sgpj_nginx  │                       │  Serviço: sgpj_nginx  │
     └───────────┬───────────┘                       └───────────┬───────────┘
                 │                                               │
                 └───────────────────────┬───────────────────────┘
                                         │
                     ┌───────────────────┴───────────────────┐
                     │ Rede Overlay Docker Swarm (sgpj_net)  │
                     │  Alias DNS interno: "api.backend"     │
                     └───────────────────┬───────────────────┘
                                         │
                 ┌───────────────────────┴───────────────────────┐
                 ▼ (:8080)                                       ▼ (:8080)
     ┌───────────────────────┐                       ┌───────────────────────┐
     │     ec2-backend-a     │                       │     ec2-backend-b     │
     │  (Subnet Privada A)   │                       │  (Subnet Privada B)   │
     │  ✦ SWARM WORKER ✦     │                       │  ✦ SWARM WORKER ✦     │
     │  Serviço: sgpj_backend│                       │  Serviço: sgpj_backend│
     └───────────┬───────────┘                       └───────────┬───────────┘
                 │                                               │
                 └───────────────────────┬───────────────────────┘
                                         │
                                         ▼ (:3306)
                             ┌───────────────────────┐
                             │        ec2-db         │
                             │ (Subnet Privada DB A) │
                             │  MySQL 8.0 Container  │
                             │   (Fora do Swarm)     │
                             └───────────────────────┘

════════════════════════════════════════════════════════════════════════════════
               SERVIÇOS TRANSVERSAIS (TODAS AS MÁQUINAS)
════════════════════════════════════════════════════════════════════════════════
   • Fluent Bit (Systemd Nativo) ───► s3://sgpj-bronze-<id>/logs/ ──► Athena
   • Node Exporter (:9100)       ───► Prometheus (:9090)          ──► Grafana
   • Grafana Alloy               ───► Loki (:3100)               ──► Grafana
```

---

## 📦 Detalhamento por Instância

### 1. `ec2-app-a` e `ec2-app-b`
- **Subnets:** `public_a` (`10.0.1.0/24`) e `public_b` (`10.0.2.0/24`)
- **Papel no Swarm:** `ec2-app-a` é o **Swarm Manager**; `ec2-app-b` é **Swarm Worker**.
- **Acesso:** Recebe tráfego externo balanceado pelo ALB na porta `80`.
- **EFS Montado:** `/mnt/efs-sgpj` (armazenamento persistente compartilhado).

| Processo / Container | Imagem / Pacote | Porta | Função |
|---|---|---|---|
| `sgpj_nginx` (Serviço Swarm) | ECR `sgpj-frontend:latest` | `80:80` | Servidor Web Nginx: serve o build React SPA e faz proxy reverso `/api/` para `http://api.backend:8080/`. |
| `fluent-bit` | Serviço nativo `systemd` | — | Coleta logs de containers, logs do Nginx e `/var/log/auth.log`, enviando compactados em Gzip para o S3 Bronze. |
| `node-exporter` | `quay.io/prometheus/node-exporter` | `9100` | Expõe métricas de CPU, memória, disco e tráfego de rede para o Prometheus. |
| `alloy` | `grafana/alloy` | — | Agente de telemetria raspando logs Docker em tempo real para o Loki. |

---

### 2. `ec2-backend-a` e `ec2-backend-b`
- **Subnets:** `private_backend_a` (`10.0.3.0/24`) e `private_backend_b` (`10.0.4.0/24`)
- **Papel no Swarm:** **Swarm Workers** (rotulados com `node.labels.role == backend`).
- **Acesso:** Totalmente isoladas da internet pública. Acessam a internet via **NAT Gateway** para download de pacotes e autenticação no ECR. Acesso SSH administrativo via Bastion / ProxyJump pela `ec2-app-a`.

| Processo / Container | Imagem / Pacote | Porta | Função |
|---|---|---|---|
| `sgpj_backend` (Serviço Swarm) | ECR `sgpj-backend:latest` | `8080:8080` | Aplicação Spring Boot 4.x / Java 21 com REST API e autenticação JWT. Responde pelo alias `api.backend`. |
| `fluent-bit` | Serviço nativo `systemd` | — | Coleta logs da aplicação Spring Boot e do SO, enviando para o S3 Bronze. |
| `node-exporter` | `quay.io/prometheus/node-exporter` | `9100` | Métricas de sistema operacional do backend para o Prometheus. |
| `alloy` | `grafana/alloy` | — | Coleta logs de stdout/stderr da JVM para o Loki. |

---

### 3. `ec2-db` (Banco de Dados)
- **Subnet:** `private_db_a` (`10.0.5.0/24`)
- **Papel no Cluster:** **Fora do Docker Swarm** (mantido como Docker Standalone por segurança e integridade de volumes de banco de dados relacional).
- **Acesso de Rede:** Porta `3306` restrita pelo Security Group apenas para o Security Group do Backend.

| Processo / Container | Imagem / Pacote | Porta | Função |
|---|---|---|---|
| `sgpj-mysql` | `mysql:8.0` | `3306:3306` | Banco de Dados relacional MySQL com dados em `/opt/mysql/data`, charset `utf8mb4` e schema inicializado automaticamente via `schema.sql`. |
| `fluent-bit` | Serviço nativo `systemd` | — | Coleta logs do MySQL e do SO para auditoria no S3 Bronze. |
| `node-exporter` | `quay.io/prometheus/node-exporter` | `9100` | Monitora utilização de recursos (I/O de disco, memória) do servidor de banco. |

---

### 4. `ec2-observability` (Central de Monitoramento e Alertas)
- **Subnet:** `public_obs` (`10.0.7.0/24` - AZ us-east-1c)
- **Acesso:** Aberto publicamente para avaliação e visualização dos dashboards da equipe.

| Container | Imagem | Porta | Função |
|---|---|---|---|
| `grafana` | `grafana/grafana` | `3001` | Interface visual de observabilidade com dashboards de infraestrutura, métricas e visualizador de logs. |
| `prometheus` | `prom/prometheus` | `9090` | Servidor de métricas com retenção em série temporal raspando todos os Node Exporters e exporters AWS. |
| `loki` | `grafana/loki` | `3100` | Servidor central de agregação e busca rápida de logs via LogQL. |
| `alertmanager` | `prom/alertmanager` | `9093` | Mecanismo de disparo e roteamento de alertas para incidentes de infraestrutura. |
| `cloudwatch-exporter` | `prom/cloudwatch-exporter` | `9106` | Consulta a API da AWS e expõe métricas de ALB, EFS e NAT Gateway no Prometheus. |
| `node-exporter` | `quay.io/prometheus/node-exporter` | `9100` | Métricas locais da própria máquina de observabilidade. |

---

## 🗄️ Serviços Gerenciados na AWS

| Recurso | Identificador / Nome | Função |
|---|---|---|
| **Elastic Container Registry (ECR)** | `sgpj-frontend` / `sgpj-backend` | Repositório privado de imagens Docker oficiais da aplicação (com proteção `prevent_destroy`). |
| **Elastic File System (EFS)** | `app_efs` | Sistema de arquivos NFS montado em `/mnt/efs-sgpj` nas instâncias de aplicação e backend. |
| **Data Lake S3** | `sgpj-bronze-<id>`<br>`sgpj-silver-<id>`<br>`sgpj-gold-<id>` | Camadas de armazenamento de dados e arquivos brutos (logs do Fluent Bit caem na Bronze). |
| **Athena S3 Results** | `sgpj-athena-results-<id>` | Armazena resultados de queries executadas no AWS Athena. |
| **AWS Glue** | `sgpj_logs_bronze` | Catálogo de metadados das tabelas de logs (`containers`, `nginx`, `os`). |
| **AWS Athena** | Workgroup: `sgpj-logs-analytics` | Mecanismo de consulta SQL sobre os logs brutos armazenados no S3 Bronze. |
