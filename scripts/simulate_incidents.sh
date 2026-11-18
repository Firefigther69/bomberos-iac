#!/usr/bin/env bash
# Generación controlada de incidentes para evidenciar la detección temprana (video / informe).
# Requiere el despliegue activo y permisos de SSM Run Command y CloudWatch.
#
# Uso: ./scripts/simulate_incidents.sh <escenario>
#   cpu       Carga de CPU durante 12 min        -> alarma ec2-cpu-alta
#   nginx     Detiene nginx durante 4 min         -> alarmas app-nginx-detenido y servicio-degradado
#   trafico   600 solicitudes, 30% a rutas 404    -> métricas HTTPRequests / HTTP4xx y dashboard
#   denegado  6 llamadas API sin permiso desde la instancia -> alarma sec-unauthorized-api-calls
#   sns       Fuerza el estado ALARM de la alarma de CPU -> prueba del canal de notificación
set -euo pipefail
cd "$(dirname "$0")/.."

SCENARIO="${1:-}"
IID="$(terraform output -raw instance_id)"
URL="$(terraform output -raw app_url)"
PREFIX="$(terraform output -raw alarm_prefix)"

run_remote() {
  local cmd_id
  cmd_id=$(aws ssm send-command --instance-ids "$IID" --document-name AWS-RunShellScript \
    --comment "Simulacion controlada: $SCENARIO" --parameters "commands=[\"$1\"]" \
    --query Command.CommandId --output text)
  echo "Comando SSM enviado: $cmd_id (queda registrado en CloudTrail como SendCommand)"
}

case "$SCENARIO" in
  cpu)
    run_remote "timeout 720 sh -c 'for i in \$(seq \$(nproc)); do yes > /dev/null & done; wait' || true"
    echo "Esperar ~10-15 min y revisar la alarma ${PREFIX}-ec2-cpu-alta." ;;
  nginx)
    run_remote "systemctl stop nginx && sleep 240 && systemctl start nginx"
    echo "Revisar ${PREFIX}-app-nginx-detenido y ${PREFIX}-servicio-degradado en 2-5 min." ;;
  trafico)
    for i in $(seq 1 600); do
      if (( i % 10 < 3 )); then path="/no-existe-$i"; else path="/"; fi
      curl -s -o /dev/null --max-time 3 "${URL}${path}" &
      (( i % 50 == 0 )) && wait
    done; wait
    echo "Tráfico generado. Ver widget 'Solicitudes HTTP por clase' del dashboard." ;;
  denegado)
    # Consulta de solo lectura que el rol de la instancia no tiene permitida (cuenta propia:
    # mínimo privilegio; Learner Lab: política de control de servicio). Se repite 6 veces
    # para superar el umbral de 5 llamadas denegadas en 5 minutos.
    BUCKET="$(terraform output -json buckets | python3 -c 'import json,sys;print(json.load(sys.stdin)["cloudtrail"])')"
    run_remote "for i in 1 2 3 4 5 6; do aws s3api get-object-lock-configuration --bucket ${BUCKET} --region us-east-1 || true; done"
    echo "Las 6 llamadas se rechazan (AccessDenied). Revisar ${PREFIX}-sec-unauthorized-api-calls en 5-10 min y la consulta 'accesos-denegados' de Logs Insights." ;;
  sns)
    aws cloudwatch set-alarm-state --alarm-name "${PREFIX}-ec2-cpu-alta" --state-value ALARM \
      --state-reason "Prueba controlada del canal de notificacion"
    echo "Revisar el correo suscrito al tópico. La alarma vuelve a OK en la siguiente evaluación." ;;
  *)
    sed -n '2,13p' "$0"; exit 1 ;;
esac
