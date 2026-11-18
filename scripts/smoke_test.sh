#!/usr/bin/env bash
# Prueba de humo posterior al despliegue (RF-01, RS-04, RS-08).
# Uso: ./scripts/smoke_test.sh [URL]   (por defecto toma `terraform output -raw app_url`)
set -euo pipefail

APP_URL="${1:-$(terraform output -raw app_url)}"
HOST="${APP_URL#http://}"
RETRIES="${RETRIES:-30}"
fail=0

check() { # descripción, comando
  if eval "$2" >/dev/null 2>&1; then echo "  [OK]    $1"; else echo "  [FALLA] $1"; fail=1; fi
}

echo "Esperando que ${APP_URL}/health responda (máx. $((RETRIES * 10)) s)..."
for i in $(seq 1 "$RETRIES"); do
  if curl -fsS --max-time 5 "${APP_URL}/health" >/dev/null 2>&1; then break; fi
  [ "$i" -eq "$RETRIES" ] && { echo "El servicio no respondió a tiempo"; exit 1; }
  sleep 10
done

echo "Pruebas de humo sobre ${APP_URL}"
check "RF-01 /health responde 200 con status ok" "curl -fsS --max-time 5 ${APP_URL}/health | grep -q '\"status\":\"ok\"'"
check "RF-01 portada responde 200"               "curl -fsS --max-time 5 -o /dev/null ${APP_URL}/"
check "RS-08 cabecera X-Content-Type-Options"   "curl -sSI --max-time 5 ${APP_URL}/ | grep -qi '^x-content-type-options: nosniff'"
check "RS-08 cabecera Content-Security-Policy"  "curl -sSI --max-time 5 ${APP_URL}/ | grep -qi '^content-security-policy:'"
check "RS-08 versión de nginx oculta"           "! curl -sSI --max-time 5 ${APP_URL}/ | grep -qi '^server: nginx/'"
check "RS-08 métodos distintos de GET bloqueados" "[ \"\$(curl -s -o /dev/null -w '%{http_code}' -X DELETE --max-time 5 ${APP_URL}/)\" = 403 ]"
check "RS-04 archivos ocultos no accesibles"     "[ \"\$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 ${APP_URL}/.env)\" = 404 ]"
check "RS-04 puerto 22 cerrado"                  "! timeout 5 bash -c \"</dev/tcp/${HOST}/22\""

exit "$fail"
