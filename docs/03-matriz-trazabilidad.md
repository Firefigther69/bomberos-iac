# Matriz de trazabilidad

Relaciona cada requerimiento con los recursos Terraform que lo implementan, las pruebas que lo verifican y la evidencia que lo demuestra. Los identificadores de evidencia (E-xx) corresponden a los archivos listados en [despliegue y evidencias](05-despliegue-y-evidencias.md#4-identificadores-de-evidencia).

**Leyenda de pruebas**
- `U:` prueba unitaria de Terraform (`tests/*.tftest.hcl`, proveedor simulado, corre en cada commit).
- `I:` prueba de integración (`tests/integration/test_infraestructura.py`, contra la cuenta real).
- `S:` prueba de humo (`scripts/smoke_test.sh`).
- `E:` prueba estática del repositorio (`tests/static/test_repositorio.py`, sin AWS, corre en cada commit).
- `P:` control del pipeline (Checkov, TFLint, gitleaks, políticas propias CKV2_BOMB_*).

> La correspondencia requerimiento → prueba se verifica automáticamente en cada ejecución del pipeline con `scripts/check_traceability.py`, que falla si algún requerimiento queda sin prueba. El último reporte generado está en `docs/evidencias/pipeline-local/trazabilidad.md`.

## Requerimientos funcionales

| Req. | Recursos Terraform | Pruebas | Evidencia |
|---|---|---|---|
| RF-01 Servicio web disponible | `aws_instance.app`, `aws_vpc_security_group_ingress_rule.app_http`, `aws_cloudwatch_metric_alarm.nginx_down`, `.http_5xx`, `aws_cloudwatch_composite_alarm.service_degraded` | S: `/health` 200, portada 200 · I: `test_rf01_health_responde_200`, `test_rf01_portada_disponible`, `test_rf03_servicio_no_degradado` · U: `rf03_alarmas_de_deteccion_temprana` | E-01, E-02, E-12 |
| RF-02 Infraestructura como código reproducible | Todo el módulo raíz, `modules/secure_bucket`, `versions.tf`, `.terraform.lock.hcl` | P: `terraform fmt`, `validate`, TFLint · U: `rf02_rt01_plan_base_sin_errores` · `E:` `test_rf02_*` (2) | E-03, E-04 |
| RF-03 Métricas y alarmas | `aws_ssm_parameter.cw_agent_config`, `aws_cloudwatch_log_metric_filter.app`, `aws_cloudwatch_metric_alarm.*` (15), `aws_cloudwatch_dashboard.main` | U: `rf03_metricas_del_sistema_operativo`, `rf03_alarmas_de_deteccion_temprana` · I: `test_rf03_alarmas_creadas_con_notificacion`, `test_rf03_metricas_del_agente_publicadas`, `test_rf03_dashboard_existe` · P: CKV2_BOMB_4 | E-05, E-06, E-07, E-11 |
| RF-04 Logs centralizados | `aws_cloudwatch_log_group.app` (5), `.vpc_flow_logs`, `.codebuild`, `.cloudtrail`, `aws_flow_log.vpc`, `aws_cloudwatch_query_definition.*` (5) | U: `rf04_logs_centralizados_y_cifrados` · I: `test_rf04_grupos_de_logs_cifrados_con_retencion`, `test_rf04_flow_logs_activos`, `test_rf04_filtros_de_metricas_de_seguridad` · P: CKV2_BOMB_3 | E-08, E-09 |
| RF-05 Auditoría y notificación | `aws_cloudtrail.main`, `module.trail_bucket`, `aws_sns_topic.alerts`, `aws_sns_topic_subscription.email`, `aws_cloudwatch_event_rule.critical_changes` | U: `rf05_auditoria_cloudtrail`, `rf05_alarmas_notifican_por_sns` · I: `test_rf05_trail_registrando`, `test_rf05_trail_multiregion_con_validacion`, `test_rf05_entrega_reciente`, `test_rf05_topico_cifrado` | E-10, E-12, E-13 |
| RF-06 Pipeline y verificación continua | `aws_codebuild_project.validate`, `.integration`, `aws_cloudwatch_event_rule.integration_schedule`, `.codebuild_failures`, `aws_cloudwatch_metric_alarm.codebuild_failed`; `buildspec/*.yml`; `.github/workflows/ci.yml` | U: `rf06_rs09_pipeline_registrado_y_cifrado`, `rf06_webhook_ejecuta_validate_en_cada_cambio` · E: `test_rf06_reportes_junit_publicados` · ejecución misma del pipeline (reportes JUnit en CodeBuild) | E-14, E-15, E-16 |
| RF-07 Administración sin SSH | `aws_iam_policy_document.ec2` (SessionManagerCore), ausencia de `key_name`, `aws_cloudwatch_query_definition.session_manager` | U: `rf07_administracion_sin_ssh`, `rs02_instancia_endurecida` · I: `test_rs04_sin_llave_ssh`, `test_rs04_puerto_ssh_cerrado` · P: CKV2_BOMB_1 | E-17 |

## Requerimientos no funcionales

| Req. | Recursos Terraform | Pruebas | Evidencia |
|---|---|---|---|
| RNF-01 Recuperación automática | `aws_cloudwatch_metric_alarm.system_check_failed` (acción `ec2:recover`), `.status_check_failed` | U: `rf03_alarmas_de_deteccion_temprana` (acción recover) | E-06 |
| RNF-02 Detección ≤ 10 min | `aws_instance.app.monitoring = true`, periodos de 60–300 s, `network_anomaly` | U: `rf03_metricas_del_sistema_operativo` (monitoring), `rf03_alarmas_de_deteccion_temprana` | E-06, E-11 |
| RNF-03 p90 < 2 s | filtro `response_time`, `aws_cloudwatch_metric_alarm.latency_high` | U: `rnf03_alarma_de_latencia_p90` · I: `test_rf03_servicio_no_degradado` | E-05 |
| RNF-04 Costo acotado | `var.instance_type` (validación), `credit_specification = standard` | U: `rt03_rnf04_rechaza_instancia_costosa`, `rnf04_control_de_costos` | E-03 |
| RNF-05 Retención ≥ 1 año | `log_retention_days = 365`, `max(…, 365)` en auditoría, ciclo de vida S3 | U: `rf04_logs_centralizados_y_cifrados` · I: `test_rf04_grupos_de_logs_cifrados_con_retencion` · P: CKV_AWS_338 | E-08 |
| RNF-06 Mantenibilidad | Estructura por dominio, `main.tf` índice, variables documentadas | E: `test_rnf06_variables_tipadas_y_documentadas`, `test_rnf06_outputs_documentados`, `test_rnf06_alarmas_citan_requerimiento` · P: TFLint (`terraform_documented_*`, `naming_convention`, `standard_module_structure`) | E-14 |
| RNF-07 Portabilidad Learner Lab | `var.use_lab_role`, `data.aws_iam_role.lab`, `data.aws_iam_instance_profile.lab` | U: `rnf07_modo_learner_lab` | E-03 |

## Requerimientos técnicos

| Req. | Recursos Terraform | Pruebas | Evidencia |
|---|---|---|---|
| RT-01 Red en 2 AZ | `aws_vpc.main`, `aws_subnet.public`, `aws_internet_gateway.main`, `aws_route_table.public` | U: `rf02_rt01_plan_base_sin_errores` | E-04 |
| RT-02 Versiones fijadas | `versions.tf`, `.terraform.lock.hcl` | E: `test_rt02_version_de_terraform_acotada`, `test_rt02_proveedores_con_restriccion_de_version`, `test_rt02_lock_file_versionado_multiplataforma` · P: `terraform init` en CI | E-14 |
| RT-03 Entradas validadas | `variables.tf` (10 reglas `validation`) | U: `variables.tftest.hcl` (6 casos de rechazo) | E-14 |
| RT-04 AL2023 + agentes | `data.aws_ssm_parameter.al2023_ami`, user data | U: `rt04_servidor_al2023_con_agentes` · E: `test_rt04_user_data_instala_agentes_y_parches` · I: `test_rf03_metricas_del_agente_publicadas` | E-07 |
| RT-05 Estado remoto seguro | `backend.hcl.example` | E: `test_rt05_backend_cifrado_con_bloqueo`, `test_rt05_estado_y_backend_excluidos_del_repositorio` | E-03 |
| RT-06 Región `us-east-1` | `var.aws_region`, `providers.tf` | U: `rt06_region_por_defecto` | E-04 |

## Requerimientos de seguridad

| Req. | Recursos Terraform | Pruebas | Evidencia |
|---|---|---|---|
| RS-01 Mínimo privilegio | `aws_iam_role.{ec2,codebuild,events,cloudtrail_logs,flow_logs}` + políticas en línea acotadas | U: `rs01_minimo_privilegio_cuenta_propia` · I: `test_rs01_rol_asociado`; simulación `denegado` · P: CKV2_BOMB_6, CKV_AWS_* IAM | E-18, E-19 |
| RS-02 Instancia endurecida | `metadata_options`, `dnf-automatic` en user data | U: `rs02_instancia_endurecida` · I: `test_rs02_imdsv2_obligatorio` · P: CKV2_BOMB_2 | E-17 |
| RS-03 Identidades humanas | `aws_iam_account_password_policy.strict`, alarmas `sec-root-account-usage`, `sec-console-login-without-mfa`, `sec-console-login-failures` | U: `rs01_minimo_privilegio_cuenta_propia` | E-13 |
| RS-04 Restricción de red | `aws_security_group.app`, reglas de entrada/salida, `aws_default_security_group.default`, `map_public_ip_on_launch = false` | U: `rs04_red_restringida` · I: `test_rs04_reglas_de_entrada_minimas`, `test_rs04_salida_solo_https`, `test_rs04_puerto_ssh_cerrado` · S: puerto 22 cerrado · P: CKV2_BOMB_5 | E-17 |
| RS-05 Cifrado | `aws_kms_key.main` (rotación), `module.*_bucket` (SSE, TLS), SNS, logs, EBS, CodeBuild | U: `rs05_cifrado_y_buckets`, `rs02_instancia_endurecida`, `rf04_…` · I: `TestProteccionDeDatos` | E-20 |
| RS-06 Credenciales y secretos | `random_password.app_secret`, `aws_ssm_parameter.app_secret` (SecureString), `.gitignore`, gitleaks | U: `rs05_cifrado_y_buckets` (SecureString) · E: `test_rs06_*` (6) · P: gitleaks (pre-commit y pipeline) | E-15, `88-parametros-ssm.txt` |
| RS-07 Trazabilidad de seguridad | `aws_cloudtrail.main`, `aws_cloudwatch_log_metric_filter.security` (10), `aws_cloudwatch_metric_alarm.security` (10), EventBridge | U: `rf05_auditoria_cloudtrail` · I: `test_rf04_filtros_de_metricas_de_seguridad` | E-10, E-13 |
| RS-08 Seguridad web | Configuración nginx en `scripts/user_data.sh.tftpl` | S: cabeceras, métodos, archivos ocultos · I: `test_rs08_cabeceras_de_seguridad` | E-02 |
| RS-09 Seguridad del pipeline | `privileged_mode = false`, `encryption_key`, Checkov bloqueante, OIDC en Actions | U: `rf06_rs09_pipeline_registrado_y_cifrado`, `rt03_rs09_rechaza_repositorio_no_https` · E: `test_rs09_*` (3) · P: Checkov 347 controles | E-15, E-16 |
