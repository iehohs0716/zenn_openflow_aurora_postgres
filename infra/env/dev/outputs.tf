output "vpc_id" {
  description = "VPC ID"
  value       = module.vpc.vpc_id
}

output "vpc_cidr" {
  description = "VPC CIDR"
  value       = module.vpc.vpc_cidr
}

output "public_subnet_ids" {
  description = "パブリックサブネット ID"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "プライベートサブネット ID"
  value       = module.vpc.private_subnet_ids
}

output "nat_gateway_id" {
  description = "NAT Gateway ID (無効時は null)"
  value       = module.vpc.nat_gateway_id
}

output "dcp_agent_security_group_id" {
  description = "DCP エージェントの SG ID"
  value       = module.dcp_agent.security_group_id
}

output "dcp_agent_instance_ids" {
  description = "DCP エージェント EC2 のインスタンス ID"
  value       = module.dcp_agent.instance_ids
}

output "bastion_security_group_id" {
  description = "踏み台の SG ID"
  value       = module.bastion.security_group_id
}

output "bastion_instance_id" {
  description = "踏み台 EC2 のインスタンス ID (SSM ポートフォワーディングの接続先)"
  value       = module.bastion.instance_id
}

output "dcp_bootstrap_token_secret_name" {
  description = "DCP ブートストラップトークンを格納する Secrets Manager のシークレット名 (値は scripts/6_sync_dcp_token.sh が投入する)"
  value       = module.dcp_token_secret.name
}

output "aurora_repl_secret_name" {
  description = "Openflow 用レプリケーションユーザー (openflow_repl) のパスワードを格納する Secrets Manager のシークレット名 (コネクタの Source Database Password に使う値)"
  value       = module.aurora_repl_secret.name
}

output "snowflake_openflow_admin_role" {
  description = "Openflow の Runtime / コネクタを操作するロール名 (Runtime にログインするユーザーのデフォルトロールにする)"
  value       = module.snowflake_openflow_roles.admin_role_name
}

output "snowflake_openflow_runtime_role" {
  description = "Openflow の Runtime の EXECUTE_AS_ROLE に指定するロール名"
  value       = module.snowflake_openflow_roles.runtime_role_name
}

output "snowflake_openflow_connector_fqn" {
  description = "Openflow のコネクタの完全修飾名"
  value       = module.snowflake_openflow_connector.fully_qualified_name
}

output "snowflake_dcp_name" {
  description = "Snowflake の DCP オブジェクト名"
  value       = module.snowflake_dcp.name
}

output "aurora_writer_endpoint" {
  description = "Aurora ライターエンドポイント (Snowflake のネットワークルールとコネクタの接続先)"
  value       = module.aurora.writer_endpoint
}

output "aurora_engine_version" {
  description = "Aurora のエンジンバージョン (AWS が解決した値)"
  value       = data.aws_rds_engine_version.aurora.version
}

output "aurora_master_user_secret_arn" {
  description = "Aurora マスターパスワードを管理する Secrets Manager シークレットの ARN"
  value       = module.aurora.master_user_secret_arn
}

output "snowflake_dcp_eai_name" {
  description = "DCP 用 EAI 名 (Openflow ランタイムに付与するもの)"
  value       = module.snowflake_dcp.eai_name
}

output "snowflake_dcp_target" {
  description = "DCP 用ネットワークルールに登録した接続先 FQDN:ポート (Openflow のコネクタにも同じ値を指定する)"
  value       = module.snowflake_dcp.target
}

output "deployment_instructions" {
  description = "Post-deployment instructions"
  value       = <<-EOT
=== リソース情報 ===
VPC:               ${module.vpc.vpc_id} (${module.vpc.vpc_cidr})
Public Subnets:    ${join(", ", module.vpc.public_subnet_ids)}
Private Subnets:   ${join(", ", module.vpc.private_subnet_ids)}
NAT Gateway:       ${coalesce(module.vpc.nat_gateway_id, "(無効)")}
DCP Agent:         ${join(", ", module.dcp_agent.instance_ids)}
Bastion:           ${module.bastion.instance_id}
Aurora (writer):   ${module.aurora.writer_endpoint}:${module.aurora.port}
DCP:               ${module.snowflake_dcp.name}
Token secret:      ${module.dcp_token_secret.name}
EAI:               ${module.snowflake_dcp.eai_name}
Rule target:       ${module.snowflake_dcp.target}
EOT
}
