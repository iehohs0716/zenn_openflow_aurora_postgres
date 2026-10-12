output "connector_name" {
  description = "コネクタ名"
  value       = snowflake_openflow_connector.this.name
}

output "fully_qualified_name" {
  description = "コネクタの完全修飾名 (<DB>.<SCHEMA>.<NAME>。SQL の ALTER OPENFLOW CONNECTOR や snow:// のパスに使う)"
  value       = "${local.database}.${local.schema}.${local.name}"
}
