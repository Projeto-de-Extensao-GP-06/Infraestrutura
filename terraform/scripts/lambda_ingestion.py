import gzip
import json
import os
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import date, datetime, timezone
from urllib.parse import unquote_plus

import boto3

s3_client = boto3.client("s3")

SOURCE_BUCKET = os.environ.get("SOURCE_BUCKET")
TARGET_BUCKET = os.environ.get("TARGET_BUCKET")
DEFAULT_START_DATE = os.environ.get("START_DATE_BR", "01/01/2015")
DEFAULT_OLINDA_TOP = int(os.environ.get("OLINDA_TOP", "50000"))

# ──────────────────────────────────────────────────────────────────────────────
# Referência: https://github.com/XAKCN/EDA_Brasil (inadimplencia_br/src/config.py)
# ──────────────────────────────────────────────────────────────────────────────
SGS_SERIES = {
    "inadimplencia_total": 21082,
    "inadimplencia_pf": 21084,
    "inadimplencia_pj": 21083,
    "selic_aa": 4189,
    "ipca_acum12m": 13522,
    "concessoes_bi": 20631,
    "saldo_credito_bi": 20539,
}

IBGE_SERIES = {
    "desemprego": {
        "agregado": 4099,
        "variavel": 4099,
        "frequencia": "trimestral",
        "coluna_valor": "desemprego",
    },
    "ipca_mensal": {
        "agregado": 1737,
        "variavel": 63,
        "frequencia": "mensal",
        "coluna_valor": "ipca_mensal",
    },
    "pib_per_capita": {
        "agregado": 6784,
        "variavel": 9812,
        "frequencia": "anual",
        "coluna_valor": "pib_per_capita",
    },
}

OLINDA_ENDPOINTS = [
    {
        "url": (
            "https://olinda.bcb.gov.br/olinda/servico/taxaJuros/versao/v2/odata/"
            "TaxasJurosMensalPorMes"
        ),
        "params": {
            "$format": "json",
            "$select": (
                "Mes,Modalidade,Posicao,InstituicaoFinanceira,"
                "TaxaJurosAoMes,TaxaJurosAoAno,cnpj8,anoMes"
            ),
        },
    },
    {
        "url": (
            "https://olinda.bcb.gov.br/olinda/servico/taxas-juros/versao/v2/odata/"
            "TaxasJurosMensalPorInstituicaoFinanceira"
        ),
        "params": {
            "$format": "json",
            "$select": (
                "Mes,InstituicaoFinanceira,Segmento,Modalidade,"
                "TaxaJurosAoMes,TaxaJurosAoAno,TaxaInadimplencia,"
                "NumeroDeContratos,BaseDeCalculo"
            ),
            "$orderby": "Mes desc",
        },
    },
]


def _http_get_json(url, timeout=30, retries=2):
    """Realiza requisição HTTP GET usando stdlib (suporta resposta GZIP) e retorna JSON."""
    headers = {
        "User-Agent": "Mozilla/5.0 (compatible; SGPJDataLakeIngestion/1.0)",
        "Accept": "application/json",
        "Accept-Encoding": "gzip, identity",
    }
    last_err = None
    for attempt in range(retries + 1):
        try:
            req = urllib.request.Request(url, headers=headers, method="GET")
            with urllib.request.urlopen(req, timeout=timeout) as resp:
                raw_bytes = resp.read()
                if raw_bytes[:2] == b"\x1f\x8b":
                    raw_bytes = gzip.decompress(raw_bytes)
                return json.loads(raw_bytes.decode("utf-8"))
        except Exception as err:
            last_err = err
            if attempt < retries:
                time.sleep(1.5 * (attempt + 1))
    raise RuntimeError(f"Falha ao acessar {url}: {last_err}") from last_err


def _parse_date_br(date_str):
    """Converte string DD/MM/YYYY ou YYYY-MM-DD para datetime.date."""
    date_str = str(date_str).strip()
    if "/" in date_str:
        return datetime.strptime(date_str, "%d/%m/%Y").date()
    return datetime.strptime(date_str[:10], "%Y-%m-%d").date()


def _split_date_windows(start_dt, end_dt, max_years=9):
    """
    Divide um intervalo de datas em janelas de no máximo `max_years` anos.
    Necessário pois a API BACEN SGS limita consultas de séries a janelas de 10 anos.
    """
    windows = []
    cur_start = start_dt
    while cur_start <= end_dt:
        try:
            cur_end = date(cur_start.year + max_years, cur_start.month, cur_start.day)
        except ValueError:
            cur_end = date(cur_start.year + max_years, cur_start.month, 28)
        if cur_end > end_dt:
            cur_end = end_dt
        windows.append((cur_start.strftime("%d/%m/%Y"), cur_end.strftime("%d/%m/%Y")))
        cur_start = date.fromordinal(cur_end.toordinal() + 1)
    return windows


def _parse_float(value):
    """Converte string numérica (com ponto ou vírgula) em float, ou retorna None se inválido."""
    if value is None:
        return None
    val_str = str(value).strip().replace(",", ".")
    if val_str in ("", "...", "-", "null", "None"):
        return None
    try:
        return float(val_str)
    except ValueError:
        return None


def fetch_bacen_sgs_serie(nome_serie, codigo_sgs, start_dt, end_dt, ingestion_iso):
    """Coleta uma série temporal da API BACEN SGS e normaliza os registros."""
    windows = _split_date_windows(start_dt, end_dt, max_years=9)
    registros_por_data = {}

    for d_ini, d_fim in windows:
        url = (
            f"https://api.bcb.gov.br/dados/serie/bcdata.sgs.{codigo_sgs}/dados"
            f"?formato=json&dataInicial={d_ini}&dataFinal={d_fim}"
        )
        dados = _http_get_json(url, timeout=30)
        if not isinstance(dados, list):
            continue

        for item in dados:
            data_raw = str(item.get("data", "")).strip()
            valor_num = _parse_float(item.get("valor"))
            if not data_raw or valor_num is None:
                continue
            try:
                dt_iso = datetime.strptime(data_raw, "%d/%m/%Y").strftime("%Y-%m-%d")
            except ValueError:
                dt_iso = data_raw

            registros_por_data[dt_iso] = {
                "data": dt_iso,
                "data_br": data_raw,
                "valor": valor_num,
                nome_serie: valor_num,
                "codigo_sgs": codigo_sgs,
                "serie": nome_serie,
                "_source": "bacen_sgs",
                "_dataset": nome_serie,
                "_ingestion_timestamp": ingestion_iso,
            }

    registros = [registros_por_data[k] for k in sorted(registros_por_data.keys())]
    if not registros:
        raise ValueError(f"Nenhum registro válido retornado para BACEN SGS {codigo_sgs} ({nome_serie})")
    return registros


def _extrair_serie_ibge(dados):
    """Extrai o dicionário {periodo: valor} da resposta padrão da API IBGE SIDRA."""
    try:
        return dados[0]["resultados"][0]["series"][0]["serie"]
    except (IndexError, KeyError, TypeError) as err:
        raise ValueError(f"Estrutura inesperada na resposta IBGE SIDRA: {err}") from err


def fetch_ibge_sidra_serie(nome_indicador, cfg, start_dt, end_dt, ingestion_iso):
    """Coleta série da API IBGE SIDRA (desemprego, IPCA mensal ou PIB per capita)."""
    agregado = cfg["agregado"]
    variavel = cfg["variavel"]
    frequencia = cfg["frequencia"]
    coluna_valor = cfg["coluna_valor"]

    url = (
        f"https://servicodados.ibge.gov.br/api/v3/agregados/{agregado}"
        f"/periodos/all/variaveis/{variavel}?localidades=BR"
    )
    dados = _http_get_json(url, timeout=30)
    serie_dict = _extrair_serie_ibge(dados)

    registros = []
    for periodo_raw, valor_raw in serie_dict.items():
        valor_num = _parse_float(valor_raw)
        if valor_num is None:
            continue

        periodo_str = str(periodo_raw).strip()
        dt_obj = None

        try:
            if frequencia == "trimestral":
                if "." in periodo_str:
                    ano_s, tri_s = periodo_str.split(".")
                elif len(periodo_str) in (5, 6):
                    ano_s, tri_s = periodo_str[:4], periodo_str[4:]
                else:
                    continue
                mes_inicio = {1: 1, 2: 4, 3: 7, 4: 10}.get(int(tri_s), 1)
                dt_obj = date(int(ano_s), mes_inicio, 1)
            elif frequencia == "mensal":
                if len(periodo_str) == 6:
                    dt_obj = date(int(periodo_str[:4]), int(periodo_str[4:6]), 1)
            elif frequencia == "anual":
                ano_int = int(periodo_str[:4])
                if start_dt.year <= ano_int <= end_dt.year:
                    dt_obj = date(ano_int, 1, 1)
        except Exception:
            continue

        if dt_obj is None:
            continue
        if frequencia != "anual" and not (start_dt <= dt_obj <= end_dt):
            continue

        registros.append(
            {
                "data": dt_obj.strftime("%Y-%m-%d"),
                "periodo_ibge": periodo_str,
                "valor": valor_num,
                coluna_valor: valor_num,
                "agregado_ibge": agregado,
                "variavel_ibge": variavel,
                "frequencia": frequencia,
                "_source": "ibge_sidra",
                "_dataset": nome_indicador,
                "_ingestion_timestamp": ingestion_iso,
            }
        )

    registros.sort(key=lambda r: r["data"])
    if not registros:
        raise ValueError(f"Nenhum registro válido encontrado no IBGE SIDRA para {nome_indicador}")
    return registros


def fetch_bacen_olinda(top, ingestion_iso):
    """
    Coleta taxas de juros e inadimplência por modalidade e instituição financeira
    via API BACEN Olinda (com fallback automático de endpoint e de top para 10.000).
    """
    tentativas = [top, 10000] if top > 10000 else [top]
    ultimo_erro = None

    for endpoint in OLINDA_ENDPOINTS:
        for tentativa_top in tentativas:
            params = dict(endpoint["params"])
            params["$top"] = tentativa_top
            query_params = urllib.parse.urlencode(
                params, quote_via=urllib.parse.quote, safe="$,"
            )
            url = f"{endpoint['url']}?{query_params}"
            try:
                print(f"[API] BACEN Olinda: solicitando top={tentativa_top} em {endpoint['url']}...")
                payload = _http_get_json(url, timeout=90, retries=1)
                valores = payload.get("value", []) if isinstance(payload, dict) else []
                if not valores:
                    raise ValueError("API BACEN Olinda retornou lista vazia.")

                registros = []
                for row in valores:
                    registro = dict(row)
                    registro["_source"] = "bacen_olinda"
                    registro["_dataset"] = "taxas_juros_modalidade"
                    registro["_ingestion_timestamp"] = ingestion_iso
                    registros.append(registro)

                return registros
            except Exception as err:
                ultimo_erro = err
                print(f"[AVISO] Falha no BACEN Olinda (top={tentativa_top}): {err}")

    raise RuntimeError(f"BACEN Olinda indisponível após todas as tentativas: {ultimo_erro}")


def save_records_to_bronze(target_bucket, source_name, dataset_name, records, now_utc):
    """Salva lista de dicionários no formato JSON Lines (NDJSON) particionado no S3 Bronze."""
    partition_path = (
        f"raw_data/{source_name}/{dataset_name}/"
        f"year={now_utc.year}/"
        f"month={now_utc.month:02d}/"
        f"day={now_utc.day:02d}/"
    )
    target_key = f"{partition_path}{dataset_name}.json"

    ndjson_body = "\n".join(json.dumps(rec, ensure_ascii=False) for rec in records) + "\n"

    s3_client.put_object(
        Bucket=target_bucket,
        Key=target_key,
        Body=ndjson_body.encode("utf-8"),
        ContentType="application/x-ndjson",
        Metadata={
            "source": source_name,
            "dataset": dataset_name,
            "record-count": str(len(records)),
            "ingestion-timestamp": now_utc.isoformat(),
            "reference-repo": "XAKCN/EDA_Brasil",
        },
    )
    print(f"[S3 BRONZE] Salvo: s3://{target_bucket}/{target_key} ({len(records)} registros)")
    return target_key


def _handle_s3_event_records(records, target_bucket):
    """Mantém compatibilidade com eventos S3 (s3:ObjectCreated:*) vindos do bucket sgpj-external."""
    processed_files = []
    for record in records:
        source_bucket = record["s3"]["bucket"]["name"]
        source_key = unquote_plus(record["s3"]["object"]["key"])
        print(f"Processando evento S3: s3://{source_bucket}/{source_key}")

        response = s3_client.get_object(Bucket=source_bucket, Key=source_key)
        file_content = response["Body"].read().decode("utf-8")

        try:
            json.loads(file_content)
        except json.JSONDecodeError as err:
            print(f"Erro ao parsear JSON ({source_key}): {err}")
            error_key = f"error/{source_key}"
            s3_client.copy_object(
                CopySource={"Bucket": source_bucket, "Key": source_key},
                Bucket=target_bucket,
                Key=error_key,
            )
            s3_client.delete_object(Bucket=source_bucket, Key=source_key)
            continue

        event_time = record.get("eventTime") or datetime.now(timezone.utc).isoformat()
        ingestion_timestamp = datetime.fromisoformat(event_time.replace("Z", "+00:00"))

        partition_path = (
            f"raw_data/s3_external/"
            f"year={ingestion_timestamp.year}/"
            f"month={ingestion_timestamp.month:02d}/"
            f"day={ingestion_timestamp.day:02d}/"
            f"hour={ingestion_timestamp.hour:02d}/"
        )
        filename = source_key.split("/")[-1]
        target_key = f"{partition_path}{filename}"

        s3_client.put_object(
            Bucket=target_bucket,
            Key=target_key,
            Body=file_content.encode("utf-8"),
            ContentType="application/json",
            Metadata={
                "source-bucket": source_bucket,
                "source-key": source_key,
                "ingestion-timestamp": event_time,
                "original-filename": filename,
            },
        )
        print(f"Arquivo S3 salvo em: s3://{target_bucket}/{target_key}")
        processed_files.append(target_key)

    return {
        "statusCode": 200,
        "body": json.dumps(
            {
                "mode": "s3_event",
                "message": "Arquivos S3 processados com sucesso",
                "files": processed_files,
            },
            ensure_ascii=False,
        ),
    }


def lambda_handler(event, context):
    """
    Handler principal da Lambda de Ingestão Bronze (SGPJ Data Lake).
    - Modo 1 (Padrão / EventBridge / Invocação Direta): Coleta dados das bases externas
      de referência do repositório XAKCN/EDA_Brasil (BACEN SGS, IBGE SIDRA e BACEN Olinda)
      e grava em JSON Lines particionado no bucket Bronze.
    - Modo 2 (Evento S3): Processa arquivos JSON enviados ao bucket sgpj-external.
    """
    event = event or {}
    target_bucket = event.get("target_bucket") or TARGET_BUCKET
    if not target_bucket:
        raise ValueError("A variável de ambiente TARGET_BUCKET não está configurada.")

    # Compatibilidade com notificações de eventos S3
    if isinstance(event, dict) and "Records" in event and event["Records"]:
        first_record = event["Records"][0]
        if isinstance(first_record, dict) and "s3" in first_record:
            return _handle_s3_event_records(event["Records"], target_bucket)

    now_utc = datetime.now(timezone.utc)
    ingestion_iso = now_utc.isoformat()

    start_date_str = event.get("data_inicial", DEFAULT_START_DATE)
    end_date_str = event.get("data_final", now_utc.strftime("%d/%m/%Y"))
    olinda_top = int(event.get("olinda_top", DEFAULT_OLINDA_TOP))
    enabled_sources = event.get(
        "sources", ["bacen_sgs", "ibge_sidra", "bacen_olinda"]
    )

    start_dt = _parse_date_br(start_date_str)
    end_dt = _parse_date_br(end_date_str)

    print(
        f"Iniciando ingestão externa EDA_Brasil -> s3://{target_bucket} | "
        f"Período: {start_dt} a {end_dt} | Fontes: {enabled_sources}"
    )

    sucesso = []
    falhas = []
    total_registros = 0

    # 1. Coleta BACEN SGS (7 séries macroeconômicas e de crédito)
    if "bacen_sgs" in enabled_sources:
        for nome_serie, codigo_sgs in SGS_SERIES.items():
            try:
                registros = fetch_bacen_sgs_serie(
                    nome_serie, codigo_sgs, start_dt, end_dt, ingestion_iso
                )
                s3_key = save_records_to_bronze(
                    target_bucket, "bacen_sgs", nome_serie, registros, now_utc
                )
                sucesso.append(
                    {
                        "source": "bacen_sgs",
                        "dataset": nome_serie,
                        "records": len(registros),
                        "s3_key": s3_key,
                    }
                )
                total_registros += len(registros)
            except Exception as err:
                msg = f"Erro em bacen_sgs.{nome_serie} (SGS {codigo_sgs}): {err}"
                print(f"[ERRO] {msg}")
                falhas.append({"source": "bacen_sgs", "dataset": nome_serie, "error": str(err)})

    # 2. Coleta IBGE SIDRA (desemprego, IPCA mensal e PIB per capita)
    if "ibge_sidra" in enabled_sources:
        for nome_indicador, cfg in IBGE_SERIES.items():
            try:
                registros = fetch_ibge_sidra_serie(
                    nome_indicador, cfg, start_dt, end_dt, ingestion_iso
                )
                s3_key = save_records_to_bronze(
                    target_bucket, "ibge_sidra", nome_indicador, registros, now_utc
                )
                sucesso.append(
                    {
                        "source": "ibge_sidra",
                        "dataset": nome_indicador,
                        "records": len(registros),
                        "s3_key": s3_key,
                    }
                )
                total_registros += len(registros)
            except Exception as err:
                msg = f"Erro em ibge_sidra.{nome_indicador}: {err}"
                print(f"[ERRO] {msg}")
                falhas.append(
                    {"source": "ibge_sidra", "dataset": nome_indicador, "error": str(err)}
                )

    # 3. Coleta BACEN Olinda (Taxas de juros e inadimplência por modalidade/instituição)
    if "bacen_olinda" in enabled_sources:
        try:
            registros = fetch_bacen_olinda(olinda_top, ingestion_iso)
            s3_key = save_records_to_bronze(
                target_bucket,
                "bacen_olinda",
                "taxas_juros_modalidade",
                registros,
                now_utc,
            )
            sucesso.append(
                {
                    "source": "bacen_olinda",
                    "dataset": "taxas_juros_modalidade",
                    "records": len(registros),
                    "s3_key": s3_key,
                }
            )
            total_registros += len(registros)
        except Exception as err:
            msg = f"Erro em bacen_olinda.taxas_juros_modalidade: {err}"
            print(f"[ERRO] {msg}")
            falhas.append(
                {
                    "source": "bacen_olinda",
                    "dataset": "taxas_juros_modalidade",
                    "error": str(err),
                }
            )

    if not sucesso and falhas:
        status_code = 500
        status_msg = "Falha total na ingestão das fontes externas"
    elif falhas:
        status_code = 207
        status_msg = "Ingestão concluída com falhas parciais"
    else:
        status_code = 200
        status_msg = "Ingestão de todas as fontes externas concluída com sucesso"

    resumo = {
        "mode": "external_api_ingestion",
        "reference": "https://github.com/XAKCN/EDA_Brasil",
        "message": status_msg,
        "target_bucket": target_bucket,
        "ingestion_timestamp": ingestion_iso,
        "total_datasets_saved": len(sucesso),
        "total_records_ingested": total_registros,
        "datasets": sucesso,
        "errors": falhas,
    }
    print(f"Resumo da execução: {json.dumps(resumo, ensure_ascii=False)}")

    return {
        "statusCode": status_code,
        "body": json.dumps(resumo, ensure_ascii=False),
    }
