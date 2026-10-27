import json
import boto3
import os
from datetime import datetime
from urllib.parse import unquote_plus

s3_client = boto3.client('s3')
SOURCE_BUCKET = os.environ.get('SOURCE_BUCKET')
TARGET_BUCKET = os.environ.get('TARGET_BUCKET')

def lambda_handler(event, context):
    """Processa arquivos JSON do bucket de origem e salva no bucket bronze com particionamento."""

    for record in event['Records']:
        try:
            source_bucket = record['s3']['bucket']['name']
            source_key = unquote_plus(record['s3']['object']['key'])
            print(f"Processando: s3://{source_bucket}/{source_key}")

            response = s3_client.get_object(Bucket=source_bucket, Key=source_key)
            file_content = response['Body'].read().decode('utf-8')

            try:
                data = json.loads(file_content)
            except json.JSONDecodeError as e:
                print(f"Erro ao parsear JSON: {e}")
                error_key = f"error/{source_key}"
                s3_client.copy_object(
                    CopySource={'Bucket': source_bucket, 'Key': source_key},
                    Bucket=TARGET_BUCKET,
                    Key=error_key
                )
                s3_client.delete_object(Bucket=source_bucket, Key=source_key)
                continue

            event_time = record['eventTime']
            ingestion_timestamp = datetime.fromisoformat(event_time.replace('Z', '+00:00'))

            partition_path = (
                f"raw_data/"
                f"year={ingestion_timestamp.year}/"
                f"month={ingestion_timestamp.month:02d}/"
                f"day={ingestion_timestamp.day:02d}/"
                f"hour={ingestion_timestamp.hour:02d}/"
            )

            filename = source_key.split('/')[-1]
            target_key = f"{partition_path}{filename}"

            s3_client.put_object(
                Bucket=TARGET_BUCKET,
                Key=target_key,
                Body=file_content,
                ContentType='application/json',
                Metadata={
                    'source-bucket': source_bucket,
                    'source-key': source_key,
                    'ingestion-timestamp': event_time,
                    'original-filename': filename
                }
            )

            print(f"Arquivo salvo em: s3://{TARGET_BUCKET}/{target_key}")

        except Exception as e:
            print(f"Erro ao processar arquivo {source_key}: {str(e)}")
            raise e

    return {
        'statusCode': 200,
        'body': json.dumps({'message': 'Arquivos processados com sucesso'})
    }
