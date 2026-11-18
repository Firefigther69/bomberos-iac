"""Pruebas de integración sobre la infraestructura desplegada.

Cada prueba indica el requerimiento que verifica (docs/03-matriz-trazabilidad.md).
"""
from __future__ import annotations

import datetime as dt
import json
import socket
import urllib.request
from urllib.parse import urlparse

import pytest


def _get(url: str, timeout: int = 10):
    req = urllib.request.Request(url, headers={"User-Agent": "bomberos-la3-integration-tests"})
    with urllib.request.urlopen(req, timeout=timeout) as resp:  # noqa: S310 (URL propia del proyecto)
        return resp.status, dict(resp.headers), resp.read().decode("utf-8")


# ---------------------------------------------------------------------------
# RF-01 · Disponibilidad del servicio web
# ---------------------------------------------------------------------------
class TestServicioWeb:
    def test_rf01_health_responde_200(self, cfg):
        status, _, body = _get(f"{cfg['app_url']}/health")
        assert status == 200
        assert json.loads(body)["status"] == "ok"

    def test_rf01_portada_disponible(self, cfg):
        status, _, body = _get(cfg["app_url"])
        assert status == 200
        assert "3ra Compañía" in body

    def test_rs08_cabeceras_de_seguridad(self, cfg):
        _, headers, _ = _get(cfg["app_url"])
        normalized = {k.lower(): v for k, v in headers.items()}
        for header in ("x-content-type-options", "x-frame-options", "content-security-policy", "referrer-policy"):
            assert header in normalized, f"Falta la cabecera {header}"
        assert "nginx/" not in normalized.get("server", ""), "La versión de nginx no debe exponerse"

    def test_rs04_puerto_ssh_cerrado(self, cfg):
        host = urlparse(cfg["app_url"]).hostname
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            s.settimeout(5)
            assert s.connect_ex((host, 22)) != 0, "El puerto 22 no debe aceptar conexiones"


# ---------------------------------------------------------------------------
# RS-02 / RS-04 / RS-05 · Endurecimiento de la instancia y la red
# ---------------------------------------------------------------------------
class TestInstanciaYRed:
    @pytest.fixture(scope="class")
    def instance(self, aws, cfg):
        res = aws["ec2"].describe_instances(InstanceIds=[cfg["instance_id"]])
        return res["Reservations"][0]["Instances"][0]

    def test_rs02_imdsv2_obligatorio(self, instance):
        assert instance["MetadataOptions"]["HttpTokens"] == "required"

    def test_rs04_sin_llave_ssh(self, instance):
        assert "KeyName" not in instance

    def test_rs05_volumenes_cifrados(self, aws, instance):
        vol_ids = [m["Ebs"]["VolumeId"] for m in instance["BlockDeviceMappings"]]
        vols = aws["ec2"].describe_volumes(VolumeIds=vol_ids)["Volumes"]
        assert vols and all(v["Encrypted"] for v in vols)

    def test_rs01_rol_asociado(self, instance):
        assert "IamInstanceProfile" in instance

    def test_rs04_reglas_de_entrada_minimas(self, aws, cfg):
        rules = aws["ec2"].describe_security_group_rules(
            Filters=[{"Name": "group-id", "Values": [cfg["security_group_id"]]}]
        )["SecurityGroupRules"]
        ingress = [r for r in rules if not r["IsEgress"]]
        assert ingress, "Debe existir al menos una regla de entrada"
        assert all(r["FromPort"] == 80 and r["ToPort"] == 80 for r in ingress)

    def test_rs04_salida_solo_https(self, aws, cfg):
        rules = aws["ec2"].describe_security_group_rules(
            Filters=[{"Name": "group-id", "Values": [cfg["security_group_id"]]}]
        )["SecurityGroupRules"]
        egress = [r for r in rules if r["IsEgress"]]
        assert all(r["IpProtocol"] == "tcp" and r["FromPort"] == 443 for r in egress)

    def test_rf04_flow_logs_activos(self, aws, cfg):
        logs = aws["ec2"].describe_flow_logs(Filter=[{"Name": "resource-id", "Values": [cfg["vpc_id"]]}])["FlowLogs"]
        assert any(f["FlowLogStatus"] == "ACTIVE" for f in logs)


# ---------------------------------------------------------------------------
# RF-05 · Auditoría
# ---------------------------------------------------------------------------
class TestAuditoria:
    def test_rf05_trail_registrando(self, aws, cfg):
        status = aws["cloudtrail"].get_trail_status(Name=cfg["trail_name"])
        assert status["IsLogging"] is True

    def test_rf05_trail_multiregion_con_validacion(self, aws, cfg):
        trail = aws["cloudtrail"].describe_trails(trailNameList=[cfg["trail_name"]])["trailList"][0]
        assert trail["IsMultiRegionTrail"] is True
        assert trail["LogFileValidationEnabled"] is True
        assert trail.get("KmsKeyId"), "El trail debe cifrarse con KMS"
        assert trail.get("CloudWatchLogsLogGroupArn"), "El trail debe enviar eventos a CloudWatch Logs"

    def test_rf05_entrega_reciente(self, aws, cfg):
        status = aws["cloudtrail"].get_trail_status(Name=cfg["trail_name"])
        last = status.get("LatestCloudWatchLogsDeliveryTime") or status.get("LatestDeliveryTime")
        assert last is not None, "CloudTrail aún no entrega eventos"
        assert dt.datetime.now(dt.timezone.utc) - last < dt.timedelta(hours=2)


# ---------------------------------------------------------------------------
# RF-03 / RF-04 · Monitoreo y logging
# ---------------------------------------------------------------------------
class TestMonitoreo:
    def test_rf03_alarmas_creadas_con_notificacion(self, aws, cfg):
        alarms = aws["cloudwatch"].describe_alarms(AlarmNamePrefix=cfg["alarm_prefix"], AlarmTypes=["MetricAlarm", "CompositeAlarm"])
        all_alarms = alarms["MetricAlarms"] + alarms["CompositeAlarms"]
        assert len(all_alarms) >= 20, f"Se esperaban al menos 20 alarmas, hay {len(all_alarms)}"
        sin_accion = [a["AlarmName"] for a in all_alarms if not a.get("AlarmActions")]
        assert not sin_accion, f"Alarmas sin acción de notificación: {sin_accion}"

    def test_rf03_servicio_no_degradado(self, aws, cfg):
        res = aws["cloudwatch"].describe_alarms(AlarmNames=[f"{cfg['alarm_prefix']}-servicio-degradado"], AlarmTypes=["CompositeAlarm"])
        assert res["CompositeAlarms"], "No existe la alarma compuesta de servicio"
        assert res["CompositeAlarms"][0]["StateValue"] != "ALARM"

    def test_rf03_metricas_del_agente_publicadas(self, aws, cfg):
        metrics = aws["cloudwatch"].list_metrics(
            Namespace=cfg["metrics_namespace"],
            Dimensions=[{"Name": "InstanceId", "Value": cfg["instance_id"]}],
            RecentlyActive="PT3H",
        )["Metrics"]
        names = {m["MetricName"] for m in metrics}
        for expected in ("mem_used_percent", "disk_used_percent", "procstat_lookup_pid_count"):
            assert expected in names, f"El agente no publica {expected}"

    def test_rf03_dashboard_existe(self, aws, cfg):
        body = json.loads(aws["cloudwatch"].get_dashboard(DashboardName=cfg["dashboard_name"])["DashboardBody"])
        assert len(body["widgets"]) >= 10

    def test_rf04_grupos_de_logs_cifrados_con_retencion(self, aws, cfg):
        groups = aws["logs"].describe_log_groups(logGroupNamePrefix=cfg["log_group_prefix"])["logGroups"]
        assert len(groups) >= 8
        for g in groups:
            assert g.get("kmsKeyId"), f"{g['logGroupName']} sin cifrado KMS"
            assert g.get("retentionInDays"), f"{g['logGroupName']} sin retención"

    def test_rf04_filtros_de_metricas_de_seguridad(self, aws, cfg):
        group = f"{cfg['log_group_prefix']}/audit/cloudtrail"
        filters = aws["logs"].describe_metric_filters(logGroupName=group)["metricFilters"]
        assert len(filters) >= 10

    def test_rf05_topico_cifrado(self, aws, cfg):
        attrs = aws["sns"].get_topic_attributes(TopicArn=cfg["sns_topic_arn"])["Attributes"]
        assert attrs.get("KmsMasterKeyId")


# ---------------------------------------------------------------------------
# RS-05 · Protección de datos en S3 y KMS
# ---------------------------------------------------------------------------
class TestProteccionDeDatos:
    @pytest.mark.parametrize("bucket_key", ["trail_bucket", "artifacts_bucket", "access_logs_bucket"])
    def test_rs05_bucket_endurecido(self, aws, cfg, bucket_key):
        bucket = cfg[bucket_key]
        pab = aws["s3"].get_public_access_block(Bucket=bucket)["PublicAccessBlockConfiguration"]
        assert all(pab.values()), f"{bucket}: bloqueo de acceso público incompleto"
        enc = aws["s3"].get_bucket_encryption(Bucket=bucket)["ServerSideEncryptionConfiguration"]["Rules"][0]
        assert enc["ApplyServerSideEncryptionByDefault"]["SSEAlgorithm"] in ("aws:kms", "AES256")
        assert aws["s3"].get_bucket_versioning(Bucket=bucket).get("Status") == "Enabled"
        policy = json.loads(aws["s3"].get_bucket_policy(Bucket=bucket)["Policy"])
        assert any(st.get("Sid") == "DenyInsecureTransport" for st in policy["Statement"])

    def test_rs05_rotacion_de_cmk(self, aws, cfg):
        assert aws["kms"].get_key_rotation_status(KeyId=cfg["kms_key_arn"])["KeyRotationEnabled"] is True
