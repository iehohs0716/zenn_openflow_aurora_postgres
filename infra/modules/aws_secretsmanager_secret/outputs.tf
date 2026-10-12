output "arn" {
  description = "シークレットの ARN (IAM ポリシーのリソースに使う)"
  value       = aws_secretsmanager_secret.this.arn
}

output "name" {
  description = "シークレット名 (aws secretsmanager のコマンドや user_data の --secret-id に使う)"
  value       = aws_secretsmanager_secret.this.name
}
