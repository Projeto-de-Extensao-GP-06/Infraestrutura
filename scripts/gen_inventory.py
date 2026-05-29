#!/usr/bin/env python3
"""
Gera infra/ansible/inventories/production.ini a partir dos outputs do Terraform.

Uso:
  cd infra/terraform

  Rodar no cmd:
  terraform output -json | py ../scripts/gen_inventory.py > ../ansible/inventories/production.ini
"""

import json
import sys

data = json.load(sys.stdin)

def val(key):
    return data[key]["value"]

def maybe_val(key, default=""):
  item = data.get(key)
  if not item:
    return default
  value = item.get("value")
  return value if value is not None else default

def maybe_bool(key, default=False):
    item = data.get(key)
    if not item:
        return default
    value = item.get("value")
    if isinstance(value, bool):
        return value
    return default

aws_auth_enabled = maybe_bool("observability_aws_auth_enabled", True)
alert_sns_topic_arn = maybe_val("alert_sns_topic_arn") if aws_auth_enabled else ""

out = f"""[app]
ec2-app-a ansible_host={val("app_a_public_ip")}
ec2-app-b ansible_host={val("app_b_public_ip")}

[observability]
ec2-observability ansible_host={val("observability_public_ip")}

[backend]
ec2-backend-a ansible_host={val("backend_a_private_ip")}
ec2-backend-b ansible_host={val("backend_b_private_ip")}

[db]
ec2-db ansible_host={val("db_private_ip")}

[private:children]
backend
db

[all:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=~/.ssh/Key-All.pem
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o ConnectTimeout=10'
efs_dns={val("efs_dns_name")}
observability_aws_auth_enabled={'true' if aws_auth_enabled else 'false'}
prometheus_enable_cloudwatch_exporter_scrape={'true' if aws_auth_enabled else 'false'}
alertmanager_sns_topic_arn={alert_sns_topic_arn}

[private:vars]
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o ConnectTimeout=10 -o ProxyJump=ubuntu@{val("app_a_public_ip")}'
"""

print(out.strip())
