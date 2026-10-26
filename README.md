# Infraestrutura — SGPJ (Grupo 06)

Repositório de infraestrutura como código (Terraform) e automação de configuração (Ansible) para a arquitetura de Nuvem e Observabilidade na AWS.

---

## 🚀 Guia Principal de Execução

- **[Passo a Passo de Implantação e Operação](./PASSO_A_PASSO.md)** — Guia prático com os comandos para build de imagens no ECR, subida do Terraform (`init` / `apply`) e orquestração automatizada do Ansible.

---

## 📚 Documentação Técnica de Arquitetura

Toda a documentação aprofundada da infraestrutura está organizada no diretório [`docs/`](./docs/):

- **[Telemetria, Logs e Auditoria](./docs/TELEMETRIA_E_LOGS.md)** — Arquitetura unificada de telemetria: fluxo do Fluent Bit, divisão Hot Storage (Loki/Grafana) vs Cold Storage (S3 Bronze/Glue/Athena) e queries analíticas de auditoria.
- **[Mapa da Infraestrutura & Swarm](./docs/MAPA_INFRAESTRUTURA.md)** — Topologia de rede, diagrama de instâncias EC2, portas, comunicação via Docker Swarm e balanceamento via ALB.
- **[Relatório de Observabilidade & Métricas](./docs/RELATORIO_OBSERVABILIDADE.md)** — Detalhamento técnico da stack de métricas (Prometheus, CloudWatch Exporter, Node Exporter) e dashboards no Grafana.
- **[Arquitetura do Data Lake Medallion](./docs/DATA_LAKE_ARCHITECTURE.md)** — Estrutura de dados das camadas Bronze, Silver e Gold no S3 com AWS Glue e processamento analítico.
- **[Relatório FinOps e Custos de Nuvem](./docs/RELATORIO_CUSTOS.md)** — Análise detalhada de custos e viabilidade orçamentária validada via Infracost e c3x para o voucher AWS Academy.
- **[Guia de Ambientes Emulados (LocalStack)](./docs/LOCALSTACK_USAGE.md)** — Guia para testes e emulação local de serviços AWS via Docker Compose.
- **[Integração Externa (OneDrive / Microsoft Graph)](./docs/INTEGRACAO_ONEDRIVE.md)** — Documentação da integração OAuth2 entre o backend Spring Boot e a API do Microsoft OneDrive.
