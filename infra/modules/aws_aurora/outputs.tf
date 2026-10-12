output "security_group_id" {
  description = "Aurora の SG ID (DCP エージェントの送信先に使う)"
  value       = aws_security_group.this.id
}

output "writer_endpoint" {
  description = "ライター (クラスタ) エンドポイントの FQDN。Snowflake のネットワークルールとコネクタの接続先に使う"
  value       = aws_rds_cluster.this.endpoint
}

output "reader_endpoint" {
  description = "リーダーエンドポイントの FQDN。論理レプリケーションには使わない"
  value       = aws_rds_cluster.this.reader_endpoint
}

output "port" {
  description = "DB ポート"
  value       = aws_rds_cluster.this.port
}

output "database_name" {
  description = "初期データベース名"
  value       = aws_rds_cluster.this.database_name
}

output "master_user_secret_arn" {
  description = "マスターパスワードを管理する Secrets Manager シークレットの ARN"
  value       = aws_rds_cluster.this.master_user_secret[0].secret_arn
}
