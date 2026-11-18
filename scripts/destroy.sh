#!/usr/bin/env bash
# Destrucción controlada del ambiente (requiere confirmación con el nombre del ambiente).
set -euo pipefail
cd "$(dirname "$0")/.."
VARS_FILE="${1:-terraform.tfvars}"
ENV_NAME="$(grep -E '^environment' "$VARS_FILE" | cut -d'"' -f2)"

read -r -p "Esto destruye el ambiente '${ENV_NAME}'. Escriba el nombre del ambiente para confirmar: " answer
[ "$answer" = "$ENV_NAME" ] || { echo "Cancelado."; exit 0; }

terraform destroy -input=false -var-file="$VARS_FILE"
rm -f outputs.json
