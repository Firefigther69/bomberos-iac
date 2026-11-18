"""Pruebas estáticas del repositorio (sin credenciales ni costo).

Validan requerimientos que no dependen de un recurso desplegado: versiones fijadas,
estado remoto seguro, ausencia de secretos, documentación del código, configuración
del pipeline y del arranque del servidor. Se ejecutan en cada commit (CI).
"""
from __future__ import annotations

import json
import re
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
TF_FILES = sorted(p for p in ROOT.glob("*.tf"))


def _read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8")


def _blocks(text: str, kind: str) -> list[tuple[str, str]]:
    """Devuelve (nombre, cuerpo) de cada bloque `kind "nombre" { ... }` balanceando llaves."""
    out = []
    for m in re.finditer(rf'^{kind} "([^"]+)"(?: "([^"]+)")? \{{', text, re.M):
        depth, i = 0, m.end() - 1
        for j in range(i, len(text)):
            depth += {"{": 1, "}": -1}.get(text[j], 0)
            if depth == 0:
                out.append((m.group(2) or m.group(1), text[i : j + 1]))
                break
    return out


# ---------------------------------------------------------------------------
# RT-02 · Versiones fijadas
# ---------------------------------------------------------------------------
def test_rt02_version_de_terraform_acotada():
    versions = _read("versions.tf")
    assert re.search(r'required_version\s*=\s*">=\s*1\.11\.0,\s*<\s*2\.0\.0"', versions)


def test_rt02_proveedores_con_restriccion_de_version():
    versions = _read("versions.tf")
    assert re.search(r'source\s*=\s*"hashicorp/aws"\s*\n\s*version\s*=\s*"~>\s*5\.\d+"', versions)
    assert re.search(r'source\s*=\s*"hashicorp/random"\s*\n\s*version\s*=\s*"~>\s*3\.\d+"', versions)


def test_rt02_lock_file_versionado_multiplataforma():
    lock = _read(".terraform.lock.hcl")
    assert 'provider "registry.terraform.io/hashicorp/aws"' in lock
    assert 'provider "registry.terraform.io/hashicorp/random"' in lock
    assert lock.count("h1:") >= 4, "El lock debe incluir hashes de varias plataformas"


# ---------------------------------------------------------------------------
# RT-05 · Estado remoto seguro
# ---------------------------------------------------------------------------
def test_rt05_backend_cifrado_con_bloqueo():
    backend = _read("backend.hcl.example")
    assert re.search(r"^encrypt\s*=\s*true", backend, re.M)
    assert re.search(r"^use_lockfile\s*=\s*true", backend, re.M)


def test_rt05_estado_y_backend_excluidos_del_repositorio():
    ignored = _read(".gitignore").splitlines()
    for pattern in ("*.tfstate", "*.tfstate.*", "backend.hcl", ".terraform/"):
        assert pattern in ignored, f"Falta {pattern} en .gitignore"


# ---------------------------------------------------------------------------
# RS-06 · Credenciales y secretos
# ---------------------------------------------------------------------------
def test_rs06_archivos_sensibles_ignorados():
    ignored = _read(".gitignore").splitlines()
    for pattern in ("*.tfvars", ".env", "*.pem", "*.key", "credentials", "outputs.json"):
        assert pattern in ignored, f"Falta {pattern} en .gitignore"
    assert "!terraform.tfvars.example" in ignored


AWS_KEY = re.compile(r"\b(AKIA|ASIA)[0-9A-Z]{16}\b")
PRIVATE_KEY = re.compile(r"-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----")


def test_rs06_sin_llaves_de_acceso_ni_privadas_en_el_codigo():
    hallazgos = []
    for path in ROOT.rglob("*"):
        if not path.is_file() or ".terraform" in path.parts or ".git" in path.parts or path.suffix in {".png", ".docx", ".svg", ".zip"}:
            continue
        text = path.read_text(encoding="utf-8", errors="ignore")
        if AWS_KEY.search(text) or PRIVATE_KEY.search(text):
            hallazgos.append(str(path.relative_to(ROOT)))
    assert not hallazgos, f"Posibles credenciales en: {hallazgos}"


def test_rs06_secreto_de_aplicacion_como_securestring_con_cmk():
    secrets = _read("secrets.tf")
    body = dict(_blocks(secrets, "resource"))["app_secret"]
    assert 'type        = "SecureString"' in body
    assert "key_id      = aws_kms_key.main.arn" in body
    assert "random_password.app_secret.result" in body


def test_rs06_ejemplo_de_variables_sin_credenciales():
    example = _read("terraform.tfvars.example").lower()
    for forbidden in ("access_key", "secret_key", "aws_secret", "password ="):
        assert forbidden not in example


def test_rs06_outputs_no_exponen_el_secreto():
    outputs = _read("outputs.tf")
    assert "random_password" not in outputs
    assert "aws_ssm_parameter.app_secret.value" not in outputs


# ---------------------------------------------------------------------------
# RNF-06 · Mantenibilidad: variables, outputs y alarmas documentadas
# ---------------------------------------------------------------------------
def test_rnf06_variables_tipadas_y_documentadas():
    for name, body in _blocks(_read("variables.tf"), "variable"):
        assert "description" in body, f"variable {name} sin description"
        assert re.search(r"^\s*type\s*=", body, re.M), f"variable {name} sin type"


def test_rnf06_outputs_documentados():
    for name, body in _blocks(_read("outputs.tf"), "output"):
        assert "description" in body, f"output {name} sin description"


def test_rnf06_alarmas_citan_requerimiento():
    text = _read("alarms.tf")
    for name, body in _blocks(text, "resource"):
        if "alarm_description" in body:
            assert re.search(r"(RF|RNF|RS)-\d{2}", body), f"alarma {name} sin ID de requerimiento"
    audit = _read("audit.tf")
    assert len(re.findall(r'description\s*=\s*"RS-\d{2}', audit)) >= 10


# ---------------------------------------------------------------------------
# RT-04 · Arranque del servidor
# ---------------------------------------------------------------------------
def test_rt04_user_data_instala_agentes_y_parches():
    ud = _read("scripts/user_data.sh.tftpl")
    assert "amazon-cloudwatch-agent" in ud
    assert "dnf-automatic" in ud
    assert "fetch-config -m ec2 -s -c \"ssm:" in ud
    assert "set -euo pipefail" in ud


def test_rs06_rs08_user_data_protege_el_secreto_y_endurece_nginx():
    ud = _read("scripts/user_data.sh.tftpl")
    assert "chmod 0640 /etc/bomberos/app.env" in ud
    assert "unset APP_SECRET" in ud
    assert "server_tokens off;" in ud
    assert "limit_except GET HEAD" in ud
    assert "http_tokens" not in ud  # IMDSv2 se controla en Terraform, no en el script


# ---------------------------------------------------------------------------
# RS-09 / RF-06 · Seguridad e integración del pipeline
# ---------------------------------------------------------------------------
def test_rs09_pipeline_ejecuta_controles_bloqueantes():
    bs = _read("buildspec/validate.yml")
    for step in ("terraform fmt -check", "terraform validate", "tflint", "gitleaks detect", "checkov", "terraform test", "pytest tests/static", "check_traceability.py"):
        assert step in bs, f"buildspec/validate.yml no ejecuta: {step}"


def test_rf06_reportes_junit_publicados():
    bs = _read("buildspec/validate.yml")
    assert bs.count("file-format: JUNITXML") >= 5


def test_rs09_github_actions_permisos_minimos():
    ci = _read(".github/workflows/ci.yml")
    assert re.search(r"^permissions:\s*\n\s*contents:\s*read", ci, re.M)
    assert "id-token: write" in ci  # OIDC solo en el job de integración
    assert "AWS_SECRET_ACCESS_KEY" not in ci


def test_rs09_politicas_propias_de_checkov():
    policies = sorted((ROOT / "policies" / "checkov").glob("*.yaml"))
    assert len(policies) >= 6
    assert "external-checks-dir" in _read(".checkov.yaml")


# ---------------------------------------------------------------------------
# RF-02 · Todo en código: sin recursos fuera de Terraform
# ---------------------------------------------------------------------------
def test_rf02_todo_archivo_tf_tiene_formato_canonico():
    result = subprocess.run(["terraform", "fmt", "-check", "-recursive"], cwd=ROOT, capture_output=True, text=True)
    if result.returncode == 127:
        pytest.skip("terraform no disponible")
    assert result.returncode == 0, result.stdout


def test_rf02_mock_cubre_datos_de_cuenta():
    mocks = _read("tests/mocks/aws.tfmock.hcl")
    for data in ("aws_caller_identity", "aws_region", "aws_availability_zones"):
        assert f'mock_data "{data}"' in mocks
