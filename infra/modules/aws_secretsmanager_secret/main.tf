terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# 値を Terraform 管理外にするシークレット。
# state に秘密を載せないため、プレースホルダで作成し、実値は
# `aws secretsmanager put-secret-value` (または専用のスクリプト) で投入する
resource "aws_secretsmanager_secret" "this" {
  name        = var.name
  description = var.description

  recovery_window_in_days = var.recovery_window_in_days
}

resource "aws_secretsmanager_secret_version" "this" {
  secret_id     = aws_secretsmanager_secret.this.id
  secret_string = "PLACEHOLDER"

  lifecycle {
    ignore_changes = [secret_string]
  }
}
