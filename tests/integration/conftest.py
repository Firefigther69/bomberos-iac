"""Configuración compartida de las pruebas de integración.

Los identificadores de la infraestructura se toman, en orden de prioridad:
1. Variables de entorno (las inyecta Terraform en el proyecto CodeBuild de integración).
2. El archivo outputs.json generado con `terraform output -json > outputs.json`.

Las pruebas son de solo lectura: no crean, modifican ni eliminan recursos.
"""
from __future__ import annotations

import json
import os
from pathlib import Path

import boto3
import pytest

ROOT = Path(__file__).resolve().parents[2]


def _load_outputs() -> dict:
    path = Path(os.environ.get("TF_OUTPUTS_FILE", ROOT / "outputs.json"))
    if not path.exists():
        return {}
    raw = json.loads(path.read_text(encoding="utf-8"))
    return {k: v.get("value") for k, v in raw.items()}


@pytest.fixture(scope="session")
def cfg() -> dict:
    out = _load_outputs()
    buckets = out.get("buckets") or {}

    def pick(env: str, default):
        return os.environ.get(env) or default

    config = {
        "region": pick("AWS_REGION", pick("AWS_DEFAULT_REGION", "us-east-1")),
        "app_url": pick("APP_URL", out.get("app_url")),
        "instance_id": pick("INSTANCE_ID", out.get("instance_id")),
        "security_group_id": pick("SECURITY_GROUP_ID", out.get("security_group_id")),
        "trail_name": pick("TRAIL_NAME", out.get("cloudtrail_name")),
        "sns_topic_arn": pick("SNS_TOPIC_ARN", out.get("sns_topic_arn")),
        "dashboard_name": pick("DASHBOARD_NAME", out.get("dashboard_name")),
        "alarm_prefix": pick("ALARM_PREFIX", out.get("alarm_prefix")),
        "kms_key_arn": pick("KMS_KEY_ARN", out.get("kms_key_arn")),
        "trail_bucket": pick("TRAIL_BUCKET", buckets.get("cloudtrail")),
        "artifacts_bucket": pick("ARTIFACTS_BUCKET", buckets.get("artifacts")),
        "access_logs_bucket": pick("ACCESS_LOGS_BUCKET", buckets.get("access_logs")),
        "vpc_id": pick("VPC_ID", out.get("vpc_id")),
        "metrics_namespace": pick("METRICS_NAMESPACE", out.get("metrics_namespace") or "BomberosLA3/EC2"),
        "log_group_prefix": pick("LOG_GROUP_PREFIX", None),
    }
    if not config["log_group_prefix"] and out.get("log_groups"):
        any_group = next(iter(out["log_groups"].values()))
        config["log_group_prefix"] = "/".join(any_group.split("/")[:3])

    missing = [k for k, v in config.items() if not v]
    if missing:
        pytest.skip(f"Faltan datos de la infraestructura desplegada: {', '.join(missing)}")
    return config


@pytest.fixture(scope="session")
def aws(cfg):
    session = boto3.session.Session(region_name=cfg["region"])
    return {name: session.client(name) for name in ("ec2", "cloudtrail", "cloudwatch", "logs", "s3", "sns", "kms")}
