#!/usr/bin/env python3
"""Exporta gráficos reales de CloudWatch como PNG (GetMetricWidgetImage).

Sirven de evidencia de monitoreo cuando no se dispone de la consola web.
Uso: python3 scripts/render_metric_images.py [horas]   (requiere outputs.json)
Salida: docs/evidencias/plataforma/graficos/*.png
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

import boto3

ROOT = Path(__file__).resolve().parents[1]
HOURS = int(sys.argv[1]) if len(sys.argv) > 1 else 3
OUT = ROOT / "docs" / "evidencias" / "plataforma" / "graficos"
OUT.mkdir(parents=True, exist_ok=True)

outputs = {k: v["value"] for k, v in json.loads((ROOT / "outputs.json").read_text()).items()}
iid = outputs["instance_id"]
ns_ec2 = outputs["metrics_namespace"]
cw = boto3.client("cloudwatch", region_name="us-east-1")


BASE = {"width": 900, "height": 380, "start": f"-PT{HOURS}H", "timezone": "-0300", "view": "timeSeries", "stacked": False}

WIDGETS = {
    "01-cpu-con-alarma": {
        "title": "CPU (%) · umbral de la alarma ec2-cpu-alta",
        "metrics": [["AWS/EC2", "CPUUtilization", "InstanceId", iid, {"label": "CPU"}]],
        "period": 60, "stat": "Average", "yAxis": {"left": {"min": 0, "max": 100}},
        "annotations": {"horizontal": [{"label": "Umbral 80 %", "value": 80, "color": "#d13212"}]},
    },
    "02-memoria-disco-swap": {
        "title": "Memoria, disco y swap (%) · agente CloudWatch",
        "metrics": [
            [ns_ec2, "mem_used_percent", "InstanceId", iid, {"label": "memoria"}],
            [ns_ec2, "disk_used_percent", "InstanceId", iid, "path", "/", "fstype", "xfs", {"label": "disco /", "stat": "Maximum"}],
            [ns_ec2, "swap_used_percent", "InstanceId", iid, {"label": "swap"}],
        ],
        "period": 60, "stat": "Average", "yAxis": {"left": {"min": 0, "max": 100}},
    },
    "03-red": {
        "title": "Red (bytes por minuto)",
        "metrics": [
            ["AWS/EC2", "NetworkIn", "InstanceId", iid, {"label": "entrada"}],
            ["AWS/EC2", "NetworkOut", "InstanceId", iid, {"label": "salida"}],
        ],
        "period": 60, "stat": "Sum",
    },
    "04-nginx-con-alarma": {
        "title": "Procesos nginx · alarma app-nginx-detenido (< 1)",
        "metrics": [[ns_ec2, "procstat_lookup_pid_count", "InstanceId", iid, "exe", "nginx", "pid_finder", "native", {"label": "procesos nginx"}]],
        "period": 60, "stat": "Minimum", "yAxis": {"left": {"min": 0}},
        "annotations": {"horizontal": [{"label": "Mínimo esperado 1", "value": 1, "color": "#d13212"}]},
    },
    "05-solicitudes-http": {
        "title": "Solicitudes HTTP por clase (desde logs JSON de nginx)",
        "metrics": [
            ["BomberosLA3/App", "HTTPRequests", {"label": "total"}],
            ["BomberosLA3/App", "HTTP4xx", {"label": "4xx", "color": "#ff9900"}],
            ["BomberosLA3/App", "HTTP5xx", {"label": "5xx", "color": "#d13212"}],
        ],
        "period": 60, "stat": "Sum",
    },
    "06-accesos-denegados": {
        "title": "Llamadas API denegadas (CloudTrail) · alarma sec-unauthorized-api-calls",
        "metrics": [["BomberosLA3/Security", "UnauthorizedAPICalls", {"label": "denegadas"}]],
        "period": 300, "stat": "Sum", "view": "bar",
        "annotations": {"horizontal": [{"label": "Umbral 5 en 5 min", "value": 5, "color": "#d13212"}]},
    },
    "07-latencia": {
        "title": "Tiempo de respuesta p90 (s) · alarma app-latencia-alta",
        "metrics": [["BomberosLA3/App", "ResponseTime", {"label": "p90", "stat": "p90"}]],
        "period": 300,
        "annotations": {"horizontal": [{"label": "Umbral 2 s", "value": 2, "color": "#d13212"}]},
    },
}

for name, spec in WIDGETS.items():
    widget = {**BASE, **spec}
    try:
        png = cw.get_metric_widget_image(MetricWidget=json.dumps(widget), OutputFormat="png")["MetricWidgetImage"]
        (OUT / f"{name}.png").write_bytes(png)
        print(f"  {OUT.relative_to(ROOT)}/{name}.png")
    except Exception as exc:  # noqa: BLE001 - se informa y se continúa con el resto
        print(f"  {name}: no se pudo generar ({exc})")
