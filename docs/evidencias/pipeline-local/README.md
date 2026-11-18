# Evidencia del pipeline de validación

Salida real de cada etapa de `buildspec/validate.yml`, ejecutada sobre el código final con las mismas versiones que el pipeline (`00-versiones.txt`). Generada el 2026-11-16.

| Etapa | Archivo | Resultado |
|---|---|---|
| Formato | `01-terraform-fmt.txt` | sin diferencias |
| Inicialización | `02-terraform-init.txt` | OK |
| Sintaxis | `03-terraform-validate.txt` | configuración válida |
| Lint | `04-tflint.txt` | 0 problemas |
| Secretos | `05-gitleaks.txt` | sin hallazgos |
| Políticas de seguridad | `06-checkov.txt` | 347 aprobados, 0 fallidos, 18 excepciones justificadas |
| Pruebas unitarias | `07-terraform-test.txt` | 24 aprobadas |
| Pruebas estáticas | `08-pytest-static.txt` | 21 aprobadas |
| Trazabilidad | `09-trazabilidad.txt`, [`trazabilidad.md`](trazabilidad.md) | 29/29 requerimientos cubiertos |
| Scripts | `10-shellcheck.txt` | 0 advertencias |
| Integración (colección) | `11-pytest-integracion-coleccion.txt` | 25 casos listos; se ejecutan tras el despliegue |

Los reportes JUnit (`reportes-junit/`) son los mismos archivos que CodeBuild publica en la pestaña *Reports*.

Reproducir: `terraform init -backend=false && terraform test && python3 -m pytest tests/static && python3 scripts/check_traceability.py`.
