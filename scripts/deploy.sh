#!/usr/bin/env bash
# Despliegue controlado: validación local -> plan guardado -> aplicación del plan revisado.
# Uso: ./scripts/deploy.sh [archivo.tfvars]
set -euo pipefail
cd "$(dirname "$0")/.."

VARS_FILE="${1:-terraform.tfvars}"
[ -f "$VARS_FILE" ] || { echo "No existe $VARS_FILE (copiar desde terraform.tfvars.example)"; exit 1; }

echo "==> Identidad AWS en uso"
aws sts get-caller-identity --query '{Cuenta:Account,Identidad:Arn}' --output table

echo "==> Inicialización"
if [ -f backend.hcl ]; then terraform init -input=false -backend-config=backend.hcl; else terraform init -input=false; fi

echo "==> Validación estática"
terraform fmt -check -recursive
terraform validate
terraform test

echo "==> Plan"
terraform plan -input=false -var-file="$VARS_FILE" -out=tfplan

read -r -p "¿Aplicar el plan anterior? (escriba 'si'): " answer
[ "$answer" = "si" ] || { echo "Cancelado."; exit 0; }

echo "==> Apply"
terraform apply -input=false tfplan
rm -f tfplan
terraform output -json > outputs.json

echo "==> Prueba de humo"
./scripts/smoke_test.sh

echo "==> Pruebas de integración en CodeBuild (solo lectura sobre la cuenta)"
PROJECT="$(terraform output -json codebuild_projects | python3 -c 'import json,sys;print(json.load(sys.stdin)["integration"])')"
BUILD_ID="$(aws codebuild start-build --project-name "$PROJECT" --query build.id --output text)"
echo "Build iniciado: $BUILD_ID"
STATUS="IN_PROGRESS"
while [ "$STATUS" = "IN_PROGRESS" ]; do
  sleep 20
  STATUS="$(aws codebuild batch-get-builds --ids "$BUILD_ID" --query 'builds[0].buildStatus' --output text)"
  echo "  estado: $STATUS"
done
[ "$STATUS" = "SUCCEEDED" ] || { echo "Las pruebas de integración fallaron (ver reportes en CodeBuild)"; exit 1; }
echo "Despliegue verificado. Ejecute ./scripts/collect_evidence.sh para generar la evidencia."
