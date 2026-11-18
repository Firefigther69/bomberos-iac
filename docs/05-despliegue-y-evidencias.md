# Despliegue de evidencia y resultados en operación

Registro del despliegue real del proyecto y de las pruebas en operación. Todas las salidas citadas están en `docs/evidencias/`.

| Dato | Valor |
|---|---|
| Fecha | 16 de noviembre de 2026, 19:50–20:20 (hora de Chile) |
| Plataforma | AWS Academy Learner Lab, región `us-east-1` |
| Modalidad | `use_lab_role = true`, `enable_codebuild = false` (ver `04-controles-seguridad.md` §8) |
| Recursos gestionados por Terraform | 121 (`plataforma/01-recursos-gestionados.txt`) |
| Aplicación | `http://<IP pública>/` y `/health` → `{"status":"ok"}` |

## 1. Resultado de las pruebas en operación

| Prueba | Resultado | Evidencia |
|---|---|---|
| Prueba de humo (`smoke_test.sh`) | 8 de 8 verificaciones correctas | `plataforma/92-prueba-de-humo.txt` |
| Pruebas de integración (pytest + boto3) | 25 de 25 aprobadas | `plataforma/93-pruebas-integracion.txt`, `53-integracion-junit.xml` |
| Integridad de los registros de auditoría | `1/1 digest files valid` | `plataforma/32-integridad-logs.txt` |
| Agente CloudWatch | 17 métricas publicadas (CPU, memoria, disco, swap, E/S, TCP, procesos) | `plataforma/11-metricas-agente.txt` |
| Alarmas | 23 alarmas de métricas + 1 compuesta, todas con acción SNS | `plataforma/20-alarmas.txt`, `capturas/E06-alarmas.jpg` |

## 2. Incidentes simulados y detección

| Hora | Acción (`simulate_incidents.sh`) | Detección | Evidencia |
|---|---|---|---|
| 20:04:21 | `nginx`: se detiene el servidor web por 4 minutos | 20:06:54 alarma `app-nginx-detenido` y alarma compuesta `servicio-degradado` en ALARM (2 min 33 s). `/health` respondía 503. Correo de alerta recibido. | `capturas/E12-incidente-nginx.jpg`, `E12b-historial-sns.jpg`, `E13-correos-alerta.png` |
| 20:08 aprox. | El script reinicia nginx | 20:09:54 ambas alarmas vuelven a OK y se envía el correo de recuperación | `plataforma/22-historial-alarmas.txt` |
| 20:02–20:04 | `denegado`: llamadas API no permitidas desde la instancia | 20:05:36 alarma `sec-unauthorized-api-calls` en ALARM. La consulta guardada `accesos-denegados` muestra 31 eventos `AccessDenied` | `capturas/E19-accesos-denegados.jpg` |
| 20:01 | `cpu`: carga sostenida de CPU | La instancia (t3.micro con créditos estándar, recién creada) agotó sus créditos y AWS limitó la CPU a su línea base, por lo que no superó el 80 %. La alarma `ec2-creditos-cpu-bajos` pasó a ALARM, que es el aviso temprano previsto para ese caso | `plataforma/graficos/01-cpu-con-alarma.png`, `plataforma/20-alarmas.txt` |
| 20:01 | `trafico`: 600 solicitudes, 30 % a rutas inexistentes | Métricas `HTTPRequests` y `HTTP4xx` generadas desde los logs JSON | `plataforma/graficos/05-solicitudes-http.png`, `capturas/E05-dashboard.jpg` |
| 20:05–20:06 | Sin intervención del equipo: la plataforma del laboratorio modificó una política IAM (`PutRolePolicy`) | 20:08:07 alarma `sec-iam-policy-changes` en ALARM y correo recibido. Demuestra la detección de cambios de terceros en la cuenta | `capturas/E13-correos-alerta.png` |

## 3. Capturas de la consola

| Archivo | Contenido | Indicador |
|---|---|---|
| `capturas/E01-aplicacion.jpg` | Aplicación web en línea | — |
| `capturas/E05-dashboard.jpg`, `E05b-dashboard-seguridad.jpg` | Dashboard: estado de alarmas, HTTP, latencia, nginx, CPU, memoria, disco, red, eventos de seguridad y accesos denegados | 1 |
| `capturas/E08-grupos-de-logs.jpg` | Los 8 grupos de logs del proyecto | 1 |
| `capturas/E06-alarmas.jpg` | Lista de alarmas con acciones habilitadas | 2 |
| `capturas/E12-incidente-nginx.jpg`, `E12b-historial-sns.jpg` | Incidente detectado, recuperado y notificado por SNS | 2 |
| `capturas/E13-correos-alerta.png` | Transcripción de los correos de alerta recibidos | 2 |
| `capturas/E10-cloudtrail.jpg` | Trail multi-región, validación de archivos y cifrado SSE-KMS | 3 |
| `capturas/E10b-cloudtrail-eventos.jpg` | Historial de eventos: cada comando enviado a la instancia, con usuario y hora | 3 |
| `capturas/E19-accesos-denegados.jpg` | Consulta de accesos denegados en Logs Insights | 3, 8 |
| `capturas/E17-session-manager.jpg` | Sesión administrativa sin SSH: IMDSv1 rechazado (401), 0 llaves SSH, secreto ilegible para el usuario de sesión | 9, 10 |
| `capturas/E17b-security-group.jpg` | Grupo de seguridad con una sola regla de entrada (HTTP) | 10 |
| `capturas/E20-s3-cifrado-etiquetas.jpg` | Bucket de auditoría: SSE-KMS y etiquetas `ManagedBy = Terraform` | 11 |

El recorrido completo del entorno en operación está en `video-evidencia.mp4` (video narrado, 4 min 57 s).

El número de cuenta se ocultó en todas las capturas y archivos.

## 4. Identificadores de evidencia

Los identificadores E-xx usados en la [matriz de trazabilidad](03-matriz-trazabilidad.md) y en [controles de seguridad](04-controles-seguridad.md) corresponden a estos archivos de `docs/evidencias/`:

| ID | Archivo | ID | Archivo |
|---|---|---|---|
| E-01 | `capturas/E01-aplicacion.jpg` | E-11 | `plataforma/graficos/01-cpu-con-alarma.png`, `plataforma/20-alarmas.txt` |
| E-02 | `plataforma/92-prueba-de-humo.txt` | E-12 | `capturas/E12-incidente-nginx.jpg`, `capturas/E12b-historial-sns.jpg` |
| E-03 | `plataforma/00-terraform-outputs.txt` | E-13 | `capturas/E13-correos-alerta.png` |
| E-04 | `plataforma/01-recursos-gestionados.txt` | E-14 | `pipeline-local/` (salida de cada etapa) |
| E-05 | `capturas/E05-dashboard.jpg`, `capturas/E05b-dashboard-seguridad.jpg` | E-15 | `pipeline-local/reportes-junit/` |
| E-06 | `capturas/E06-alarmas.jpg` | E-16 | `plataforma/93-pruebas-integracion.txt`, `plataforma/53-integracion-junit.xml` |
| E-07 | `plataforma/11-metricas-agente.txt`, `plataforma/graficos/02-memoria-disco-swap.png` | E-17 | `capturas/E17-session-manager.jpg`, `capturas/E17b-security-group.jpg` |
| E-08 | `capturas/E08-grupos-de-logs.jpg` | E-18 | `iam.tf` (políticas de mínimo privilegio) |
| E-09 | `plataforma/14-ultimos-logs-nginx.txt` | E-19 | `capturas/E19-accesos-denegados.jpg` |
| E-10 | `capturas/E10-cloudtrail.jpg`, `capturas/E10b-cloudtrail-eventos.jpg`, `plataforma/32-integridad-logs.txt` | E-20 | `capturas/E20-s3-cifrado-etiquetas.jpg` |

## 5. Hallazgos del despliegue real

El primer despliegue descubrió tres restricciones del laboratorio que las pruebas con proveedor simulado no podían anticipar. Las tres se resolvieron en código y quedaron cubiertas por la prueba `rnf07_modo_learner_lab`:

1. La cuenta niega `s3:GetBucketObjectLockConfiguration`, que Terraform invoca al leer un bucket. Solución: el contenedor del bucket se declara con `aws_cloudformation_stack` cuando `use_lab_role = true`.
2. `LabRole` no admite a CodeBuild como entidad de confianza. Solución: variable `enable_codebuild`.
3. `LabRole` no admite a VPC Flow Logs. Solución: entrega de Flow Logs a S3.
