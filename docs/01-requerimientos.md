# Requerimientos del proyecto

Los requerimientos son la referencia contra la cual se evalúan el monitoreo, las pruebas automatizadas y los controles de seguridad. Cada uno tiene un identificador único que se usa en el código (descripciones de alarmas, mensajes de prueba) y en la [matriz de trazabilidad](03-matriz-trazabilidad.md).

## 1. Contexto

La 3ra Compañía del Cuerpo de Bomberos de Los Ángeles registra asistencias, emergencias, voluntarios y estado del material mayor en planillas y mensajería. La información queda dispersa, sin respaldo y sin registro de quién la modificó. El proyecto despliega en AWS la plataforma web de gestión operativa de la compañía, con una infraestructura reproducible, observable, auditada y protegida.

**Actores**

| Actor | Necesidad |
|---|---|
| Voluntarios y oficiales | Consultar y registrar información operativa desde el navegador |
| Equipo DevOps (integrantes del proyecto) | Desplegar y modificar la infraestructura de forma segura y trazable |
| Directiva de la compañía | Saber cuándo el sistema falla y quién hizo cada cambio |

## 2. Requerimientos funcionales

| ID | Requerimiento | Criterio de aceptación |
|---|---|---|
| RF-01 | El sistema web debe estar disponible para los voluntarios por HTTP. | `/health` responde 200 con `{"status":"ok"}`; la portada responde 200. |
| RF-02 | Toda la infraestructura debe declararse como código versionado y reproducible. | `terraform apply` crea el ambiente completo desde cero; no existen recursos creados por consola. |
| RF-03 | El entorno debe recolectar métricas de CPU, memoria, disco, red, procesos y aplicación, y alertar desviaciones. | Métricas visibles en el dashboard; alarmas por cada métrica crítica. |
| RF-04 | Los registros de aplicación, sistema operativo, red y pipeline deben centralizarse. | Grupos de CloudWatch Logs reciben eventos de nginx, `/var/log/messages`, `/var/log/secure`, VPC Flow Logs y CodeBuild. |
| RF-05 | Toda acción sobre la cuenta debe quedar auditada y los incidentes deben notificarse. | CloudTrail activo en todas las regiones; alarmas notifican al tópico SNS de alertas. |
| RF-06 | Cada cambio debe validarse automáticamente en un pipeline antes de desplegarse, y la infraestructura desplegada debe verificarse periódicamente. | CodeBuild/GitHub Actions ejecutan validación en cada push; pruebas de integración diarias. |
| RF-07 | La administración de servidores debe realizarse sin SSH y con registro de cada sesión. | Session Manager operativo; sesiones visibles en CloudTrail (`StartSession`). |

## 3. Requerimientos no funcionales

| ID | Atributo | Requerimiento | Métrica |
|---|---|---|---|
| RNF-01 | Disponibilidad | Recuperación automática ante falla del hardware subyacente. | Alarma `StatusCheckFailed_System` con acción `ec2:recover`. |
| RNF-02 | Detección temprana | Incidentes críticos detectados en 10 minutos o menos. | Métricas EC2 a 1 min; alarmas de 2 a 10 min de ventana. |
| RNF-03 | Rendimiento | Percentil 90 del tiempo de respuesta bajo 2 segundos. | Métrica `ResponseTime` p90. |
| RNF-04 | Costo | Operación dentro del presupuesto de laboratorio. | Instancias t3/t3a micro–medium (validado); estimado USD 15–25/mes. |
| RNF-05 | Retención | Logs operativos y de auditoría retenidos al menos un año. | `retention_in_days` ≥ 365. |
| RNF-06 | Mantenibilidad | Código modular, documentado y con entradas validadas. | `terraform validate`, TFLint y documentación de variables/outputs sin hallazgos. |
| RNF-07 | Portabilidad | Desplegable en cuenta propia y en AWS Academy Learner Lab. | Variable `use_lab_role`. |

## 4. Requerimientos técnicos

| ID | Requerimiento |
|---|---|
| RT-01 | VPC `10.20.0.0/16` con dos subredes públicas en zonas de disponibilidad distintas, Internet Gateway y tabla de rutas propia. |
| RT-02 | Terraform ≥ 1.11, proveedor AWS `~> 5.80`, proveedor random `~> 3.6`, con `.terraform.lock.hcl` versionado. |
| RT-03 | Todas las variables tipadas, documentadas y con reglas de validación donde aplique. |
| RT-04 | Servidor Amazon Linux 2023 con nginx, agente CloudWatch y agente SSM; configuración del agente en Parameter Store. |
| RT-05 | Estado remoto en S3 cifrado, versionado y con bloqueo nativo (`use_lockfile`). |
| RT-06 | Región `us-east-1` por defecto (compatible con Learner Lab y eventos de servicios globales). |

## 5. Estándares de seguridad adoptados

El proyecto adopta como línea base:

- **CIS Amazon Web Services Foundations Benchmark v3.0** (secciones de IAM, logging y monitoreo).
- **AWS Well-Architected Framework**, pilares de Seguridad, Excelencia Operativa y Fiabilidad.
- **OWASP Secure Headers Project** para la capa HTTP.
- **Políticas propias** codificadas en `policies/checkov/` (CKV2_BOMB_1 a CKV2_BOMB_6).

| ID | Requerimiento de seguridad | Estándar de referencia |
|---|---|---|
| RS-01 | Mínimo privilegio: un rol por función, permisos acotados a ARN del proyecto, sin políticas administradas amplias, sesiones ≤ 1 h. | CIS 1.16, WA SEC03 |
| RS-02 | Instancia endurecida: IMDSv2 obligatorio, hop limit 1, parches de seguridad automáticos. | CIS 5.6, WA SEC06 |
| RS-03 | Identidades humanas controladas: política de contraseñas, alertas por uso de root, login sin MFA y fallos de autenticación. | CIS 1.8–1.9, 4.2–4.3, 4.6 |
| RS-04 | Restricción de red: sin puertos administrativos, entrada solo 80, salida solo 443, SG por defecto vacío, sin IP pública automática. | CIS 5.2–5.4 |
| RS-05 | Cifrado en reposo con CMK rotada y en tránsito (TLS ≥ 1.2 obligatorio en S3 y SNS). | CIS 2.1, 3.5, WA SEC08–09 |
| RS-06 | Protección de credenciales: ningún secreto en código ni variables; secretos en SecureString; escaneo de secretos en commits y pipeline; sin llaves de acceso estáticas. | CIS 1.4, WA SEC02 |
| RS-07 | Trazabilidad y detección de eventos de seguridad: trail multi-región con validación de integridad y 10 alarmas CIS. | CIS 3.1–3.2, 4.1–4.15 |
| RS-08 | Seguridad de la aplicación web: cabeceras de seguridad, versión del servidor oculta, solo métodos GET/HEAD. | OWASP Secure Headers |
| RS-09 | Seguridad del pipeline: análisis de políticas (Checkov) bloqueante, CodeBuild sin modo privilegiado, artefactos cifrados, OIDC en lugar de llaves en GitHub. | WA SEC11 |
