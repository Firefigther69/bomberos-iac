############################################
# Sistema de Gestión de la Configuración · bomberos-la3
#
# Punto de entrada del módulo raíz. Los recursos se agrupan por dominio en
# archivos separados para facilitar la revisión y la asignación de responsables:
#
#   versions.tf / providers.tf   Versiones fijadas y etiquetado por defecto
#   variables.tf / locals.tf     Entradas validadas y nomenclatura común
#   network.tf                   VPC, subredes, IGW, rutas, SG por defecto, Flow Logs
#   security_groups.tf           Reglas de red de la aplicación
#   kms.tf                       CMK con rotación y política por servicio
#   iam.tf                       Roles de mínimo privilegio (EC2, CodeBuild, EventBridge, CloudTrail)
#   secrets.tf                   Secretos en Parameter Store (SecureString)
#   s3.tf + modules/secure_bucket Buckets endurecidos (auditoría, artefactos, accesos)
#   compute.tf                   Instancia EC2 (IMDSv2, EBS cifrado, sin SSH)
#   logging.tf                   Grupos de logs, agente CloudWatch, filtros y consultas
#   alarms.tf                    Alarmas de infraestructura, SO, aplicación y pipeline
#   audit.tf                     CloudTrail, alarmas CIS y notificación en tiempo real
#   dashboard.tf                 Dashboard operativo
#   sns.tf                       Canal de alertas cifrado
#   cicd.tf                      Proyectos CodeBuild y verificación programada
#   outputs.tf                   Salidas consumidas por pruebas y operación
############################################
