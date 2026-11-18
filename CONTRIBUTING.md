# Guía de contribución

## Flujo de trabajo

1. Crear una rama desde `main`: `feature/<área>-<descripción>` (ej. `feature/obs-alarma-latencia`).
2. Instalar los controles locales una sola vez: `pip install pre-commit && pre-commit install`.
3. Hacer commits pequeños con el formato *Conventional Commits*:
   - `feat(alarms): agrega alarma de latencia p90 (RNF-03)`
   - `fix(iam): limita PutMetricData al namespace del proyecto (RS-01)`
   - `test(security): valida IMDSv2 obligatorio (RS-02)`
   - `docs(informe): justificación de métricas`
4. Incluir el ID del requerimiento afectado en el mensaje cuando corresponda.
5. Abrir un *pull request* hacia `main`. Debe pasar GitHub Actions antes del merge.
6. Después del merge, desplegar con `./scripts/deploy.sh` y ejecutar CodeBuild `integration`.

## Reglas

- Nunca subir credenciales, `terraform.tfvars`, archivos de estado ni `outputs.json` (gitleaks y `.gitignore` lo impiden).
- No crear ni modificar recursos desde la consola: todo cambio pasa por Terraform.
- Toda excepción de Checkov se declara en línea con justificación: `#checkov:skip=ID:motivo`.
- Toda alarma nueva incluye en `alarm_description` el requerimiento que protege y una acción de notificación.
- Todo requerimiento nuevo se agrega a `docs/01-requerimientos.md` y a la matriz de trazabilidad.
