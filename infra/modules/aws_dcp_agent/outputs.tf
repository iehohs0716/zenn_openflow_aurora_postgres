output "security_group_id" {
  description = "DCP エージェントの SG ID (DB 側 SG の許可元に使う)"
  value       = aws_security_group.agent.id
}

output "instance_ids" {
  description = "DCP エージェント EC2 のインスタンス ID"
  value       = aws_instance.agent[*].id
}
