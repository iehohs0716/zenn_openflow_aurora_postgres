output "security_group_id" {
  description = "踏み台の SG ID (DB 側 SG の許可元に使う)"
  value       = aws_security_group.bastion.id
}

output "instance_id" {
  description = "踏み台 EC2 のインスタンス ID (SSM ポートフォワーディングの接続先)"
  value       = aws_instance.bastion.id
}
