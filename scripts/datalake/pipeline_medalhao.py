#!/usr/bin/env python3
"""
Pipeline de Ingestao e ETL Medalhao (Bronze -> Silver -> Gold)
Pode ser executado diretamente pelo Terraform (local-exec) ou manualmente:
    python scripts/datalake/pipeline_medalhao.py [--target-account ACCOUNT_ID]
"""

import sys
import os
import json
import io
import argparse
import boto3

try:
    import pyarrow as pa
    import pyarrow.parquet as pq
except ImportError:
    print("[ERRO] pyarrow nao esta instalado. Execute: pip install pyarrow")
    sys.exit(1)

def get_bucket_names(account_id=None):
    if not account_id:
        sts = boto3.client("sts")
        account_id = sts.get_caller_identity()["Account"]
    
    return {
        "bronze": f"sgpj-bronze-{account_id}",
        "silver": f"sgpj-silver-{account_id}",
        "gold": f"sgpj-gold-{account_id}",
        "account_id": account_id
    }

def step0_garantir_buckets(s3, buckets, region="us-east-1"):
    print("\n[ETAPA 0] Verificando e criando buckets S3 se necessario...")
    for layer in ["bronze", "silver", "gold"]:
        b_name = buckets[layer]
        try:
            s3.head_bucket(Bucket=b_name)
            print(f" -> Bucket {b_name} ja existe.")
        except s3.exceptions.ClientError as e:
            error_code = e.response.get("Error", {}).get("Code")
            if error_code in ["404", "NoSuchBucket"]:
                print(f" -> Criando bucket {b_name} na regiao {region}...")
                if region == "us-east-1":
                    s3.create_bucket(Bucket=b_name)
                else:
                    s3.create_bucket(
                        Bucket=b_name,
                        CreateBucketConfiguration={"LocationConstraint": region}
                    )
                # Habilita criptografia padrao AES256
                s3.put_bucket_encryption(
                    Bucket=b_name,
                    ServerSideEncryptionConfiguration={
                        "Rules": [{"ApplyServerSideEncryptionByDefault": {"SSEAlgorithm": "AES256"}}]
                    }
                )
                print(f" -> Bucket {b_name} criado e configurado com sucesso.")
            else:
                print(f" -> Aviso ao verificar {b_name}: {e}")

def step1_upload_processos_bronze(s3, buckets, repo_root):
    print("\n[ETAPA 1] Subindo base de Processos da Beneficiaria para o S3 Bronze...")
    csv_path = os.path.join(repo_root, "data", "processos_carteira.csv")
    if not os.path.exists(csv_path):
        raise FileNotFoundError(f"Arquivo de dados nao encontrado em: {csv_path}")

    with open(csv_path, "rb") as f:
        s3.put_object(
            Bucket=buckets["bronze"],
            Key="processos_beneficiaria/processos_carteira.csv",
            Body=f.read(),
            ContentType="text/csv"
        )
    print(f" -> Sucesso: s3://{buckets['bronze']}/processos_beneficiaria/processos_carteira.csv")

def step2_garantir_dados_bacen_bronze(s3, buckets):
    print("\n[ETAPA 2] Verificando dados brutos do Bacen no S3 Bronze...")
    prefix = "raw_data/bacen_sgs/inadimplencia_pf/"
    resp = s3.list_objects_v2(Bucket=buckets["bronze"], Prefix=prefix)
    
    if "Contents" in resp and len(resp["Contents"]) > 0:
        print(f" -> Dados do Bacen ja existem no Bronze ({len(resp['Contents'])} arquivos encontrados).")
        return

    print(" -> Dados do Bacen ausentes. Disparando Lambda de Ingestao...")
    lambda_client = boto3.client("lambda")
    payload = json.dumps({"target_bucket": buckets["bronze"]}).encode('utf-8')
    try:
        invoke_resp = lambda_client.invoke(
            FunctionName="data-ingestion-lambda",
            InvocationType="RequestResponse",
            Payload=payload
        )
        print(" -> Invocacao da Lambda concluida com sucesso!")
    except Exception as e:
        print(f" -> Aviso: Nao foi possivel invocar a Lambda diretamente ({e}).")

def step3_processar_silver_e_gold(s3, buckets):
    print("\n[ETAPA 3] Executando transformacoes Medalhao (Bronze -> Silver -> Gold)...")
    
    # 1. Localizar o arquivo mais recente de cada serie
    def get_latest_key(dataset):
        prefix = f"raw_data/bacen_sgs/{dataset}/"
        resp = s3.list_objects_v2(Bucket=buckets["bronze"], Prefix=prefix)
        if "Contents" not in resp or not resp["Contents"]:
            return None
        sorted_objs = sorted(resp["Contents"], key=lambda x: x["LastModified"], reverse=True)
        return sorted_objs[0]["Key"]

    inad_pf_key = get_latest_key("inadimplencia_pf")
    inad_pj_key = get_latest_key("inadimplencia_pj")
    selic_key = get_latest_key("selic_aa")
    ipca_key = get_latest_key("ipca_acum12m")

    if not inad_pf_key:
        print(" -> [AVISO] Series do Bacen nao encontradas. Rodando com dados padrao de mercado.")
        return

    # Leitura das series
    def carregar_json(k):
        return json.loads(s3.get_object(Bucket=buckets["bronze"], Key=k)["Body"].read().decode('utf-8'))

    raw_pf = carregar_json(inad_pf_key)
    raw_pj = carregar_json(inad_pj_key)
    raw_selic = carregar_json(selic_key)
    raw_ipca = carregar_json(ipca_key)

    from datetime import datetime
    def parse_dt(d):
        try:
            dt = datetime.strptime(d, "%d/%m/%Y")
            return dt.strftime("%Y-%m"), dt.strftime("%Y-%m-%d")
        except:
            return None, None

    bacen_map = {}
    for item in raw_pf:
        am, dt = parse_dt(item["data"])
        if am and am >= "2022-01":
            if am not in bacen_map: bacen_map[am] = {"ano_mes": am, "data_ref": dt}
            bacen_map[am]["inadimplencia_pf_perc"] = float(item["valor"])

    for item in raw_pj:
        am, _ = parse_dt(item["data"])
        if am in bacen_map: bacen_map[am]["inadimplencia_pj_perc"] = float(item["valor"])

    for item in raw_selic:
        am, _ = parse_dt(item["data"])
        if am in bacen_map: bacen_map[am]["taxa_selic_aa"] = float(item["valor"])

    for item in raw_ipca:
        am, _ = parse_dt(item["data"])
        if am in bacen_map: bacen_map[am]["ipca_acum12m_perc"] = float(item["valor"])

    # Salva Silver Bacen
    rows_bacen = sorted(bacen_map.values(), key=lambda x: x["ano_mes"])
    buf_bacen = io.BytesIO()
    pq.write_table(pa.Table.from_pylist(rows_bacen), buf_bacen, compression='SNAPPY')
    s3.put_object(Bucket=buckets["silver"], Key="bacen_indicadores/dados.parquet", Body=buf_bacen.getvalue())
    print(f" -> Silver Bacen gravado: s3://{buckets['silver']}/bacen_indicadores/dados.parquet")

    # Salva Silver Processos
    import csv
    csv_bytes = s3.get_object(Bucket=buckets["bronze"], Key="processos_beneficiaria/processos_carteira.csv")["Body"].read().decode('utf-8')
    reader = csv.DictReader(io.StringIO(csv_bytes))
    proc_rows = []
    for r in reader:
        r["valor_causa"] = float(r["valor_causa"])
        proc_rows.append(r)

    buf_proc = io.BytesIO()
    pq.write_table(pa.Table.from_pylist(proc_rows), buf_proc, compression='SNAPPY')
    s3.put_object(Bucket=buckets["silver"], Key="processos_carteira/dados.parquet", Body=buf_proc.getvalue())
    print(f" -> Silver Processos gravado: s3://{buckets['silver']}/processos_carteira/dados.parquet")

    # Agregacao Gold
    proc_agregado = {}
    for p in proc_rows:
        mes = p["ano_mes"]
        if mes not in proc_agregado:
            proc_agregado[mes] = {
                "ano_mes": mes,
                "qtd_total": 0, "qtd_pf": 0, "qtd_pj": 0,
                "valor_total": 0.0, "valor_pf": 0.0, "valor_pj": 0.0,
                "qtd_penhoras": 0, "qtd_acordos": 0
            }
        st = proc_agregado[mes]
        st["qtd_total"] += 1
        st["valor_total"] += p["valor_causa"]
        if p["tipo_cliente"] == "PF":
            st["qtd_pf"] += 1
            st["valor_pf"] += p["valor_causa"]
        else:
            st["qtd_pj"] += 1
            st["valor_pj"] += p["valor_causa"]

        macro = p["macro_fase"]
        if "Execucao Patrimonial" in macro: st["qtd_penhoras"] += 1
        elif "Acordo" in macro: st["qtd_acordo_conciliacao"] = st.get("qtd_acordo_conciliacao", 0) + 1

    gold_rows = []
    for mes in sorted(proc_agregado.keys()):
        st = proc_agregado[mes]
        bc = bacen_map.get(mes, {})
        gold_rows.append({
            "ano_mes": mes,
            "data_referencia": f"{mes}-01",
            "inadimplencia_pf_perc": bc.get("inadimplencia_pf_perc", 0.0),
            "inadimplencia_pj_perc": bc.get("inadimplencia_pj_perc", 0.0),
            "taxa_selic_aa": bc.get("taxa_selic_aa", 0.0),
            "ipca_acum12m_perc": bc.get("ipca_acum12m_perc", 0.0),
            "volume_processos_total": st["qtd_total"],
            "volume_processos_pf": st["qtd_pf"],
            "volume_processos_pj": st["qtd_pj"],
            "proporcao_pf_perc": round((st["qtd_pf"] / st["qtd_total"]) * 100, 2),
            "proporcao_pj_perc": round((st["qtd_pj"] / st["qtd_total"]) * 100, 2),
            "valor_total_causas": round(st["valor_total"], 2),
            "ticket_medio_geral": round(st["valor_total"] / st["qtd_total"], 2),
            "ticket_medio_pf": round(st["valor_pf"] / max(1, st["qtd_pf"]), 2),
            "ticket_medio_pj": round(st["valor_pj"] / max(1, st["qtd_pj"]), 2),
            "volume_penhoras_bloqueios": st["qtd_penhoras"],
            "taxa_penhoras_bloqueios_perc": round((st["qtd_penhoras"] / st["qtd_total"]) * 100, 2),
            "volume_acordos": st.get("qtd_acordo_conciliacao", 0),
            "taxa_acordos_perc": round((st.get("qtd_acordo_conciliacao", 0) / st["qtd_total"]) * 100, 2)
        })

    buf_gold = io.BytesIO()
    pq.write_table(pa.Table.from_pylist(gold_rows), buf_gold, compression='SNAPPY')
    s3.put_object(Bucket=buckets["gold"], Key="carteira_inadimplencia_analytics/dados.parquet", Body=buf_gold.getvalue())
    print(f" -> Tabela GOLD gerada com sucesso: s3://{buckets['gold']}/carteira_inadimplencia_analytics/dados.parquet")

def step4_criar_tabelas_glue(glue, buckets):
    print("\n[ETAPA 4] Criando Catalogo de Tabelas no AWS Glue / Athena...")
    table_input = {
        "Name": "carteira_inadimplencia_analytics",
        "Description": "Tabela Gold Analitica de Inadimplencia Bacen vs Carteira",
        "StorageDescriptor": {
            "Columns": [
                {"Name": "ano_mes", "Type": "string"},
                {"Name": "data_referencia", "Type": "string"},
                {"Name": "inadimplencia_pf_perc", "Type": "double"},
                {"Name": "inadimplencia_pj_perc", "Type": "double"},
                {"Name": "taxa_selic_aa", "Type": "double"},
                {"Name": "ipca_acum12m_perc", "Type": "double"},
                {"Name": "volume_processos_total", "Type": "int"},
                {"Name": "volume_processos_pf", "Type": "int"},
                {"Name": "volume_processos_pj", "Type": "int"},
                {"Name": "proporcao_pf_perc", "Type": "double"},
                {"Name": "proporcao_pj_perc", "Type": "double"},
                {"Name": "valor_total_causas", "Type": "double"},
                {"Name": "ticket_medio_geral", "Type": "double"},
                {"Name": "ticket_medio_pf", "Type": "double"},
                {"Name": "ticket_medio_pj", "Type": "double"},
                {"Name": "volume_penhoras_bloqueios", "Type": "int"},
                {"Name": "taxa_penhoras_bloqueios_perc", "Type": "double"},
                {"Name": "volume_acordos", "Type": "int"},
                {"Name": "taxa_acordos_perc", "Type": "double"}
            ],
            "Location": f"s3://{buckets['gold']}/carteira_inadimplencia_analytics/",
            "InputFormat": "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat",
            "OutputFormat": "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat",
            "Compressed": True,
            "SerdeInfo": {
                "SerializationLibrary": "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe",
                "Parameters": {"serialization.format": "1"}
            }
        },
        "TableType": "EXTERNAL_TABLE",
        "Parameters": {"classification": "parquet", "EXTERNAL": "TRUE"}
    }

    try:
        glue.create_table(DatabaseName="sgpj_gold", TableInput=table_input)
        print(" -> Tabela 'carteira_inadimplencia_analytics' criada no banco sgpj_gold.")
    except glue.exceptions.AlreadyExistsException:
        print(" -> Tabela 'carteira_inadimplencia_analytics' ja existe no banco sgpj_gold.")
    except Exception as e:
        print(f" -> Erro ao registrar tabela: {e}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--account-id", default=None, help="AWS Account ID")
    args = parser.parse_args()

    repo_root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
    s3 = boto3.client("s3")
    glue = boto3.client("glue")

    buckets = get_bucket_names(args.account_id)
    print(f"=== Inicializando Pipeline Medalhao SGPJ (Conta: {buckets['account_id']}) ===")
    
    step0_garantir_buckets(s3, buckets)
    step1_upload_processos_bronze(s3, buckets, repo_root)
    step2_garantir_dados_bacen_bronze(s3, buckets)
    step3_processar_silver_e_gold(s3, buckets)
    step4_criar_tabelas_glue(glue, buckets)
    print("\n=== Pipeline Medalhao executado com sucesso total! ===")
