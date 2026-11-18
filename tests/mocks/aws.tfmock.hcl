# Valores simulados realistas para que las pruebas unitarias evalúen expresiones
# que dependen de ARN, cuentas o zonas de disponibilidad.

mock_data "aws_caller_identity" {
  defaults = {
    account_id = "123456789012"
    arn        = "arn:aws:iam::123456789012:user/ci"
  }
}

mock_data "aws_region" {
  defaults = {
    name = "us-east-1"
  }
}

mock_data "aws_partition" {
  defaults = {
    partition  = "aws"
    dns_suffix = "amazonaws.com"
  }
}

mock_data "aws_availability_zones" {
  defaults = {
    names = ["us-east-1a", "us-east-1b", "us-east-1c"]
  }
}

mock_data "aws_iam_policy_document" {
  defaults = {
    json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
  }
}

mock_data "aws_ssm_parameter" {
  defaults = {
    value = "ami-0123456789abcdef0"
  }
}

mock_data "aws_iam_role" {
  defaults = {
    arn  = "arn:aws:iam::123456789012:role/LabRole"
    name = "LabRole"
  }
}

mock_data "aws_iam_instance_profile" {
  defaults = {
    arn  = "arn:aws:iam::123456789012:instance-profile/LabInstanceProfile"
    name = "LabInstanceProfile"
  }
}

mock_resource "aws_kms_key" {
  defaults = {
    arn    = "arn:aws:kms:us-east-1:123456789012:key/11111111-2222-3333-4444-555555555555"
    key_id = "11111111-2222-3333-4444-555555555555"
  }
}

mock_resource "aws_s3_bucket" {
  defaults = {
    arn = "arn:aws:s3:::bomberos-la3-dev-mock"
  }
}

mock_resource "aws_cloudwatch_log_group" {
  defaults = {
    arn = "arn:aws:logs:us-east-1:123456789012:log-group:/bomberos-la3/dev/mock"
  }
}

mock_resource "aws_sns_topic" {
  defaults = {
    arn = "arn:aws:sns:us-east-1:123456789012:bomberos-la3-dev-alerts"
  }
}

mock_resource "aws_iam_role" {
  defaults = {
    arn = "arn:aws:iam::123456789012:role/bomberos-la3-dev-mock"
  }
}

mock_resource "aws_codebuild_project" {
  defaults = {
    arn = "arn:aws:codebuild:us-east-1:123456789012:project/bomberos-la3-dev-mock"
  }
}

mock_resource "aws_instance" {
  defaults = {
    id        = "i-0abc1234def567890"
    public_ip = "203.0.113.10"
    # Valor computado cuando la configuración no define key_name. Si alguien agrega
    # key_name al código, el valor configurado reemplaza este y la prueba RS-04 falla.
    key_name = ""
  }
}

mock_resource "aws_cloudwatch_metric_alarm" {
  defaults = {
    arn = "arn:aws:cloudwatch:us-east-1:123456789012:alarm:mock"
  }
}

mock_resource "aws_cloudwatch_composite_alarm" {
  defaults = {
    arn = "arn:aws:cloudwatch:us-east-1:123456789012:alarm:mock-composite"
  }
}

mock_resource "aws_cloudformation_stack" {
  defaults = {
    outputs = { BucketName = "bomberos-la3-dev-mock" }
  }
}
