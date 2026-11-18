#!/usr/bin/env bash
# Recolecta evidencia verificable del entorno desplegado (criterios de monitoreo,
# trazabilidad, pruebas y seguridad) en docs/evidencias/plataforma/.
# Solo realiza llamadas de lectura. El número de cuenta se enmascara en todos los archivos.
#
# Uso: ./scripts/collect_evidence.sh
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="docs/evidencias/plataforma"
mkdir -p "$OUT"
ACCOUNT="$(aws sts get-caller-identity --query Account --output text)"
REGION="$(aws configure get region || echo us-east-1)"
PREFIX="$(terraform output -raw alarm_prefix)"
IID="$(terraform output -raw instance_id)"
SG="$(terraform output -raw security_group_id)"
TRAIL="$(terraform output -raw cloudtrail_name)"
DASH="$(terraform output -raw dashboard_name)"
KMS="$(terraform output -raw kms_key_arn)"
TRAIL_BUCKET="$(terraform output -json buckets | python3 -c 'import json,sys;print(json.load(sys.stdin)["cloudtrail"])')"
LOG_PREFIX="$(terraform output -json log_groups | python3 -c 'import json,sys;g=json.load(sys.stdin)["cloudtrail"];print("/".join(g.split("/")[:3]))')"
PROJECTS="$(terraform output -json codebuild_projects)"

save() { # archivo, comando...
  local file="$OUT/$1"; shift
  { echo "# $(date -Is) · $*"; echo; "$@" 2>&1 || true; } | sed -E "s/${ACCOUNT}/XXXXXXXXXXXX/g; s/([A-Za-z0-9])[A-Za-z0-9._%+-]*@/\\1***@/g" > "$file"
  echo "  ${file}"
}

echo "Generando evidencias en ${OUT}/"

# --- Inventario -----------------------------------------------------------
save 00-terraform-outputs.txt terraform output
save 01-recursos-gestionados.txt terraform state list

# --- Criterio 1: métricas y registros ---------------------------------------
save 10-grupos-de-logs.txt aws logs describe-log-groups --log-group-name-prefix "$LOG_PREFIX" \
  --query 'logGroups[].{Grupo:logGroupName,RetencionDias:retentionInDays,KMS:kmsKeyId!=null,Bytes:storedBytes}' --output table
save 11-metricas-agente.txt aws cloudwatch list-metrics --namespace BomberosLA3/EC2 \
  --dimensions Name=InstanceId,Value="$IID" --query 'Metrics[].MetricName' --output table
save 12-metricas-aplicacion.txt aws cloudwatch list-metrics --namespace BomberosLA3/App --query 'Metrics[].MetricName' --output table
save 13-filtros-de-metricas.txt aws logs describe-metric-filters --log-group-name "${LOG_PREFIX}/app/nginx-access" \
  --query 'metricFilters[].{Filtro:filterName,Patron:filterPattern,Metrica:metricTransformations[0].metricName}' --output table
save 14-ultimos-logs-nginx.txt aws logs filter-log-events --log-group-name "${LOG_PREFIX}/app/nginx-access" --limit 15 \
  --query 'events[].message' --output text
save 15-dashboard-widgets.txt aws cloudwatch get-dashboard --dashboard-name "$DASH" --query DashboardName --output text

# --- Criterio 2: alarmas y notificaciones -----------------------------------
save 20-alarmas.txt aws cloudwatch describe-alarms --alarm-name-prefix "$PREFIX" \
  --query 'MetricAlarms[].{Alarma:AlarmName,Estado:StateValue,Metrica:MetricName,Umbral:Threshold,Acciones:length(AlarmActions)}' --output table
save 21-alarma-compuesta.txt aws cloudwatch describe-alarms --alarm-names "${PREFIX}-servicio-degradado" --alarm-types CompositeAlarm \
  --query 'CompositeAlarms[].{Alarma:AlarmName,Estado:StateValue,Regla:AlarmRule}' --output table
save 22-historial-alarmas.txt aws cloudwatch describe-alarm-history --alarm-name "${PREFIX}-app-nginx-detenido" \
  --history-item-type StateUpdate --max-records 10 --query 'AlarmHistoryItems[].[Timestamp,HistorySummary]' --output table
save 23-suscripciones-sns.txt aws sns list-subscriptions-by-topic --topic-arn "$(terraform output -raw sns_topic_arn)" \
  --query 'Subscriptions[].{Protocolo:Protocol,Destino:Endpoint,Estado:SubscriptionArn}' --output table
save 24-reglas-eventbridge.txt aws events list-rules --name-prefix "$PREFIX" --query 'Rules[].{Regla:Name,Estado:State,Programacion:ScheduleExpression}' --output table

# --- Criterio 3: trazabilidad -----------------------------------------------
save 30-trail-configuracion.txt aws cloudtrail describe-trails --trail-name-list "$TRAIL" --output json
save 31-trail-estado.txt aws cloudtrail get-trail-status --name "$TRAIL" --output json
save 32-integridad-logs.txt aws cloudtrail validate-logs --trail-arn "arn:aws:cloudtrail:${REGION}:${ACCOUNT}:trail/${TRAIL}" \
  --start-time "$(date -u -d '-6 hours' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -v-6H +%Y-%m-%dT%H:%M:%SZ)"
save 33-ultimos-eventos.txt aws cloudtrail lookup-events --max-results 25 \
  --query 'Events[].{Hora:EventTime,Evento:EventName,Usuario:Username,Origen:EventSource}' --output table
save 34-eventos-instancia.txt aws cloudtrail lookup-events --lookup-attributes AttributeKey=ResourceName,AttributeValue="$IID" --max-results 15 \
  --query 'Events[].{Hora:EventTime,Evento:EventName,Usuario:Username}' --output table
save 35-sesiones-ssm.txt aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=StartSession --max-results 10 \
  --query 'Events[].{Hora:EventTime,Usuario:Username}' --output table
save 36-alarmas-seguridad.txt aws cloudwatch describe-alarms --alarm-name-prefix "${PREFIX}-sec-" \
  --query 'MetricAlarms[].{Alarma:AlarmName,Estado:StateValue,Descripcion:AlarmDescription}' --output table

# --- Criterios 5 a 7: pruebas en el pipeline --------------------------------
for key in validate integration; do
  name="$(python3 -c "import json,sys;print(json.loads(sys.argv[1]).get('$key',''))" "$PROJECTS")"
  [ -n "$name" ] || { echo "  (CodeBuild deshabilitado: enable_codebuild = false)"; continue; }
  save "50-codebuild-${key}.txt" aws codebuild batch-get-builds --ids "$(aws codebuild list-builds-for-project --project-name "$name" --max-items 1 --query 'ids[0]' --output text)" \
    --query 'builds[0].{Proyecto:projectName,Estado:buildStatus,Inicio:startTime,Fin:endTime,Fases:phases[].[phaseType,phaseStatus]}' --output json
done
save 52-reportes-pruebas.txt aws codebuild list-reports --max-results 10 --query 'reports' --output json
[ -f reports/integration.xml ] && cp reports/integration.xml "$OUT/53-integracion-junit.xml"

# --- Criterios 8 a 11: seguridad --------------------------------------------
save 80-roles-iam.txt aws iam list-roles --query "Roles[?starts_with(RoleName, '${PREFIX}')].{Rol:RoleName,SesionMax:MaxSessionDuration}" --output table
for role in ec2-app codebuild events-start-build cloudtrail-to-cwlogs vpc-flow-logs; do
  pol="$(aws iam list-role-policies --role-name "${PREFIX}-${role}" --query 'PolicyNames[0]' --output text 2>/dev/null || echo None)"
  [ "$pol" != "None" ] && save "81-politica-${role}.json" aws iam get-role-policy --role-name "${PREFIX}-${role}" --policy-name "$pol" --query PolicyDocument --output json
  save "82-politicas-administradas-${role}.txt" aws iam list-attached-role-policies --role-name "${PREFIX}-${role}" --output table
done
save 83-reglas-security-group.txt aws ec2 describe-security-group-rules --filters Name=group-id,Values="$SG" \
  --query 'SecurityGroupRules[].{Salida:IsEgress,Protocolo:IpProtocol,Desde:FromPort,Hasta:ToPort,Origen:CidrIpv4}' --output table
save 84-instancia-endurecida.txt aws ec2 describe-instances --instance-ids "$IID" \
  --query 'Reservations[0].Instances[0].{IMDS:MetadataOptions.HttpTokens,HopLimit:MetadataOptions.HttpPutResponseHopLimit,LlaveSSH:KeyName,Perfil:IamInstanceProfile.Arn,Monitoreo:Monitoring.State}' --output table
save 85-volumenes-cifrados.txt aws ec2 describe-volumes --filters Name=attachment.instance-id,Values="$IID" \
  --query 'Volumes[].{Volumen:VolumeId,Cifrado:Encrypted,KMS:KmsKeyId}' --output table
save 86-kms-rotacion.txt aws kms get-key-rotation-status --key-id "$KMS" --output table
save 87-s3-auditoria.txt bash -c "aws s3api get-bucket-encryption --bucket $TRAIL_BUCKET; aws s3api get-public-access-block --bucket $TRAIL_BUCKET; aws s3api get-bucket-versioning --bucket $TRAIL_BUCKET"
save 88-parametros-ssm.txt aws ssm describe-parameters --parameter-filters Key=Path,Option=Recursive,Values="/$(terraform output -raw alarm_prefix | sed 's/-dev$//;s/-qa$//;s/-prod$//')" \
  --query 'Parameters[].{Nombre:Name,Tipo:Type,KMS:KeyId}' --output table
save 89-ssm-instancia-gestionada.txt aws ssm describe-instance-information --filters Key=InstanceIds,Values="$IID" \
  --query 'InstanceInformationList[].{Instancia:InstanceId,Ping:PingStatus,Agente:AgentVersion}' --output table
save 90-politica-contrasenas.txt aws iam get-account-password-policy --output table
save 91-acceso-ssh-cerrado.txt bash -c "timeout 5 bash -c '</dev/tcp/$(terraform output -raw app_url | sed 's#http://##')/22' && echo 'PUERTO 22 ABIERTO' || echo 'Puerto 22 cerrado: conexion rechazada o sin respuesta'"
save 92-prueba-de-humo.txt ./scripts/smoke_test.sh

echo "Listo. Revise los archivos antes de subirlos al repositorio."
