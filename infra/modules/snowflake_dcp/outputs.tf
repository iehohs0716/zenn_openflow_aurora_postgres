# 出力は、値が変数だけで決まるため、depends_on でリソースへの依存を明示する。
# 依存がないと、-target 付きの apply で state に保存されず、直後の terraform output が失敗する

output "name" {
  description = "DCP オブジェクト名。この出力を参照するリソースは、DCP の作成後に作られる"
  value       = var.name

  depends_on = [snowflake_execute.dcp]
}

output "eai_name" {
  description = "DCP 用 EAI 名 (Openflow ランタイムに付与するもの)"
  value       = var.eai_name

  depends_on = [snowflake_execute.dcp_association]
}

output "network_rule_fqn" {
  description = "ネットワークルールの完全修飾名"
  value       = local.rule_fqn

  depends_on = [snowflake_execute.dcp_association]
}

output "target" {
  description = "ネットワークルールに登録した接続先 (FQDN:ポート)。コネクタにも同じ値を指定する"
  value       = local.target

  depends_on = [snowflake_execute.dcp_association]
}
