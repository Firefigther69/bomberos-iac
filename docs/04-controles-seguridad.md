# Controles de seguridad y su trazabilidad

Este documento registra cada control de seguridad del proyecto contra el estándar adoptado (ver [requerimientos](01-requerimientos.md), sección 5). Para cada control indica dónde se implementa, cómo se verifica automáticamente y qué evidencia lo demuestra.

**Estándares de referencia**
- **CIS AWS Foundations Benchmark v3.0.0** (CIS, 2024)
- **AWS Well-Architected Framework, pilar de Seguridad**: identificadores SEC01–SEC11 (AWS, s.f.-e)
- **OWASP Secure Headers Project** (OWASP Foundation, s.f.)
- **Estándares propios del equipo**, codificados como políticas Checkov `CKV2_BOMB_1` a `CKV2_BOMB_6`

**Cómo se mantiene la trazabilidad de los controles**
1. Cada control está en código Terraform versionado. Git registra quién lo cambió, cuándo y por qué (*commit* + *pull request*).
2. Checkov evalúa 347 controles en cada *commit* y bloquea el pipeline si alguno falla.
3. Cada excepción se declara en línea con `#checkov:skip=ID:justificación` junto al recurso, de modo que aparece en el mismo *diff* que el cambio.
4. CloudTrail registra en la cuenta cualquier cambio a estos controles, y 10 alarmas notifican los cambios críticos.
5. Las pruebas de integración diarias detectan si un control fue desactivado fuera de Terraform (deriva).

Los archivos de evidencia `80-*`, `81-*`, `82-*` y `90-*` se generan con `scripts/collect_evidence.sh` en una cuenta propia; en AWS Academy Learner Lab esos roles y la política de contraseñas no existen (ver sección 8).

## 1. Gestión de identidades y mínimo privilegio (RS-01, RS-03)

| Control | Estándar | Implementación | Verificación automática | Evidencia |
|---|---|---|---|---|
| Un rol por función, sin compartir identidades | WA SEC03-BP02 | `iam.tf`: roles `ec2-app`, `codebuild`, `events-start-build`, `cloudtrail-to-cwlogs`, `vpc-flow-logs` | `rs01_minimo_privilegio_cuenta_propia` | `81-politica-*.json`, E-18 |
| Sin políticas administradas amplias (`*FullAccess`, `AdministratorAccess`) | CIS 1.16 | Solo políticas en línea; se reemplazó `AmazonSSMManagedInstanceCore` por los permisos mínimos de Session Manager | `82-politicas-administradas-*.txt` vacío; Checkov CKV_AWS_274 | `82-*.txt` |
| Permisos acotados por recurso (ARN) | WA SEC03-BP01 | Logs: solo grupos propios. SSM: solo `parameter/bomberos-la3/dev/*`. S3: solo buckets del proyecto. EventBridge: solo `StartBuild` del proyecto de integración | Checkov CKV_AWS_355/356 (excepciones justificadas solo en acciones sin soporte de recurso) | `81-politica-ec2-app.json` |
| Permisos condicionados | WA SEC03-BP01 | `cloudwatch:namespace = BomberosLA3/EC2`; `kms:ViaService = ssm`; `aws:SourceAccount` / `aws:SourceArn` en todas las relaciones de confianza (evita el problema del *confused deputy*) | Revisión en PR | `81-*.json` |
| Pipeline de solo lectura sobre la infraestructura | WA SEC11 | Rol CodeBuild: solo `Describe*`/`Get*` para las pruebas | Prueba `denegado` de `simulate_incidents.sh` | E-19 |
| Sesiones de corta duración | WA SEC02-BP02 | `max_session_duration = 3600` en todos los roles | Política propia `CKV2_BOMB_6`; `rs01_…` | `80-roles-iam.txt` |
| Política de contraseñas robusta | CIS 1.8, 1.9 | 14 caracteres, complejidad, 24 sin repetición, 90 días | `rs01_minimo_privilegio_cuenta_propia` | `90-politica-contrasenas.txt` |
| Uso de root, login sin MFA y fuerza bruta alertados | CIS 4.3, 4.2, 4.6 | Filtros y alarmas `sec-root-account-usage`, `sec-console-login-without-mfa`, `sec-console-login-failures`; EventBridge para root | `rf05_auditoria_cloudtrail` | `36-alarmas-seguridad.txt` |

## 2. Credenciales y secretos (RS-06)

| Control | Estándar | Implementación | Verificación automática | Evidencia |
|---|---|---|---|---|
| Sin llaves de acceso estáticas | CIS 1.4, WA SEC02-BP02 | EC2 y CodeBuild usan credenciales temporales del rol; GitHub Actions usa OIDC | `test_rs09_github_actions_permisos_minimos` | `.github/workflows/ci.yml` |
| Secreto generado, no escrito | WA SEC02-BP03 | `random_password` → `aws_ssm_parameter` SecureString cifrado con la CMK | `rs05_cifrado_y_buckets`, `test_rs06_secreto_de_aplicacion_como_securestring_con_cmk` | `88-parametros-ssm.txt` |
| Entrega del secreto por rol, con permisos de archivo restringidos | WA SEC02-BP03 | `user_data`: `/etc/bomberos/app.env` con permisos `0640` y `unset` de la variable | `test_rs06_rs08_user_data_protege_el_secreto_y_endurece_nginx` | — |
| Secretos nunca en outputs | — | `outputs.tf` expone solo el nombre del parámetro | `test_rs06_outputs_no_exponen_el_secreto` | `00-terraform-outputs.txt` |
| Archivos sensibles fuera del repositorio | WA SEC02 | `.gitignore`: `*.tfvars`, `*.tfstate`, `.env`, `*.pem`, `credentials`, `backend.hcl` | `test_rs06_archivos_sensibles_ignorados`, `test_rt05_…` | — |
| Escaneo de secretos en tres puntos | WA SEC11-BP02 | gitleaks en pre-commit, GitHub Actions y CodeBuild (historial completo); `detect-aws-credentials` y `detect-private-key` | `test_rs06_sin_llaves_de_acceso_ni_privadas_en_el_codigo` | `gitleaks.txt`, E-15 |
| Estado de Terraform protegido | WA SEC08 | Backend S3 cifrado, versionado y con bloqueo | `test_rt05_backend_cifrado_con_bloqueo` | `backend.hcl.example` |

## 3. Restricción de accesos (RS-04, RF-07)

| Control | Estándar | Implementación | Verificación automática | Evidencia |
|---|---|---|---|---|
| Sin puertos administrativos | CIS 5.2, 5.3 | Sin regla 22/3389; sin `key_name`; administración por Session Manager | `CKV2_BOMB_1`, `CKV2_BOMB_5`, `rs04_red_restringida`, `test_rs04_puerto_ssh_cerrado`, prueba de humo | `83-reglas-security-group.txt`, `91-acceso-ssh-cerrado.txt`, E-17 |
| Entrada mínima | CIS 5.2 | Solo TCP 80 desde `allowed_http_cidrs` (parametrizable a la IP de la compañía) | `rs04_red_restringida`, `test_rs04_reglas_de_entrada_minimas` | `83-*.txt` |
| Salida restringida | WA SEC05-BP02 | Solo TCP 443 | `test_rs04_salida_solo_https` | `83-*.txt` |
| SG por defecto sin reglas | CIS 5.4 | `aws_default_security_group` vacío | `rs04_red_restringida` | — |
| Sin IP pública automática | WA SEC05-BP01 | `map_public_ip_on_launch = false` | `rs04_red_restringida` | — |
| Buckets privados | CIS 2.1.4 | Bloqueo total de acceso público + `BucketOwnerEnforced` (sin ACL) | `TestProteccionDeDatos` | `87-s3-auditoria.txt`, E-20 |
| Protección de evidencia de auditoría | CIS 3.3 | `DenyAuditLogDeletion` salvo para `Role=audit-admin` | Revisión en PR | `s3.tf` |
| Superficie HTTP mínima | OWASP | nginx: solo GET/HEAD, bloqueo de archivos ocultos, sin versión expuesta | Prueba de humo (3 verificaciones) | `92-prueba-de-humo.txt`, E-02 |

## 4. Protección de datos (RS-05)

| Control | Estándar | Implementación | Verificación automática | Evidencia |
|---|---|---|---|---|
| CMK propia con rotación | CIS 3.6, WA SEC08-BP01 | `aws_kms_key.main` con rotación cada 365 días | `rs05_cifrado_y_buckets`, `test_rs05_rotacion_de_cmk` | `86-kms-rotacion.txt` |
| Uso de la llave por servicio | WA SEC08-BP01 | Política de llave con contexto de cifrado (`aws:logs:arn`, `aws:cloudtrail:arn`) y `SourceAccount` | Checkov CKV_AWS_33 | `kms.tf` |
| Cifrado en reposo en todo el entorno | WA SEC08-BP02 | EBS, CloudWatch Logs, CloudTrail, S3, SNS, Parameter Store, CodeBuild | `CKV2_BOMB_3`, `rf04_…`, `rs02_…`, `rf06_rs09_…` | `10-*.txt`, `85-*.txt` |
| Cifrado en tránsito | WA SEC09-BP02 | S3 y SNS niegan solicitudes sin TLS; S3 exige TLS ≥ 1.2 | `test_rs05_bucket_endurecido` | `87-*.txt` |
| Versionado y ciclo de vida | CIS 3.x | Versionado en los 3 buckets; transición a STANDARD_IA; expiración de versiones antiguas | Checkov CKV_AWS_21 | `87-*.txt` |

## 5. Endurecimiento y operación segura (RS-02, RS-08)

| Control | Estándar | Implementación | Verificación automática | Evidencia |
|---|---|---|---|---|
| IMDSv2 obligatorio, *hop limit* 1 | CIS 5.6 | `metadata_options` | `CKV2_BOMB_2`, `rs02_…`, `test_rs02_imdsv2_obligatorio` | `84-instancia-endurecida.txt` |
| Parches de seguridad automáticos | WA SEC06-BP01 | `dnf update --security` en el arranque + `dnf-automatic` | `test_rt04_user_data_instala_agentes_y_parches` | — |
| Cabeceras de seguridad | OWASP Secure Headers | CSP, X-Frame-Options, X-Content-Type-Options, Referrer-Policy, Permissions-Policy | Prueba de humo, `test_rs08_cabeceras_de_seguridad` | E-02 |
| AMI actualizada | WA SEC06 | AMI desde el parámetro público de AL2023 | `rt04_servidor_al2023_con_agentes` | — |

## 6. Seguridad del pipeline y política como código (RS-09)

| Control | Estándar | Implementación | Verificación automática | Evidencia |
|---|---|---|---|---|
| Análisis de seguridad bloqueante | WA SEC11-BP02 | Checkov (347 controles) en pre-commit, Actions y CodeBuild | Ejecución misma del pipeline | `checkov.txt`, E-15 |
| Estándares propios codificados | WA SEC01-BP06 | `policies/checkov/` (6 políticas) | `test_rs09_politicas_propias_de_checkov` | — |
| Excepciones auditables | — | 18 `#checkov:skip` con justificación en línea | Revisión en PR | Ver sección 7 |
| Build sin privilegios y cifrado | WA SEC11 | `privileged_mode = false`, `encryption_key` = CMK, artefactos en bucket endurecido | `rf06_rs09_pipeline_registrado_y_cifrado` | E-14 |
| Permisos mínimos en GitHub | WA SEC11 | `permissions: contents: read`; `id-token: write` solo en el job de integración | `test_rs09_github_actions_permisos_minimos` | `ci.yml` |
| Entradas validadas | WA SEC11 | 10 reglas `validation` (incluye URL HTTPS del repositorio) | `variables.tftest.hcl` (6 casos) | — |

## 7. Registro de excepciones (riesgos aceptados)

| ID Checkov | Recurso | Justificación | Mitigación |
|---|---|---|---|
| CKV_AWS_88 | `aws_instance.app` (IP pública) | ADR-02: evita NAT + ALB por costo | Sin puertos administrativos, SG mínimo, IMDSv2 |
| CKV_AWS_260 | Regla de entrada HTTP | Servicio web para voluntarios | Origen parametrizable (`allowed_http_cidrs`) |
| CKV_AWS_111 / 356 | Políticas EC2 y CodeBuild | Acciones que AWS no permite acotar por recurso (`PutMetricData`, `Describe*`, canal SSM) | Condición por *namespace*; solo lectura |
| CKV_AWS_109 / 111 / 356 | Política de la llave KMS | `Resource: *` en una política de llave se refiere a la propia llave | Condiciones por servicio y contexto de cifrado |
| CKV_AWS_252 | CloudTrail | SNS por cada archivo entregado genera ruido | Alarmas por filtros y EventBridge |
| CKV_AWS_394 | Zonas de disponibilidad | `slice()` fija las primeras N zonas | — |
| CKV2_AWS_34 (×2) | Parámetros SSM no sensibles | Configuración pública del agente y de la app | El secreto sí es SecureString + CMK |
| CKV2_AWS_62 / CKV_AWS_144 | Módulo de buckets | Sin consumidores de eventos; replicación fuera del presupuesto | Eventos de datos de CloudTrail; versionado |

## 8. Limitaciones conocidas: AWS Academy Learner Lab

El despliegue de evidencia se realizó en AWS Academy Learner Lab. La cuenta aplica políticas de control de servicio (SCP) que obligaron a tres adaptaciones, todas declaradas en código y activadas con `use_lab_role = true`:

| Restricción | Adaptación | Control que se mantiene |
|---|---|---|
| `LabRole` no admite `codebuild.amazonaws.com` como entidad de confianza | `enable_codebuild = false`: la validación corre en GitHub Actions y las pruebas de integración con `scripts/deploy.sh` | Mismos 9 controles y 25 pruebas de integración |
| La SCP niega `s3:GetBucketObjectLockConfiguration`, que Terraform invoca al leer `aws_s3_bucket` | El contenedor del bucket se crea con `aws_cloudformation_stack` desde Terraform | Cifrado, versionado, bloqueo público, TLS, ciclo de vida y registro siguen gestionados por Terraform y verificados por pruebas |
| `LabRole` no admite `vpc-flow-logs.amazonaws.com` | Flow Logs entregados a S3 (sin rol) | Registro de todo el tráfico de la VPC |

En Learner Lab tampoco se pueden crear roles IAM. Con `use_lab_role = true` la instancia, CodeBuild y EventBridge usan `LabRole`, que tiene más permisos de los necesarios. Este riesgo es propio de la plataforma académica, no del diseño: el código de mínimo privilegio existe, se valida con `rs01_minimo_privilegio_cuenta_propia` y se activa automáticamente en cualquier cuenta real (`use_lab_role = false`).
