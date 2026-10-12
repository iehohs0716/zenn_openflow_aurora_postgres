output "fully_qualified_name" {
  description = "シークレットの完全修飾名 (<DB>.<SCHEMA>.<NAME>)。コネクタの config.json の fullyQualifiedSecretName に使う"
  value       = "${local.database}.${local.schema}.${local.name}"
}

output "name" {
  description = "シークレット名 (大文字)"
  value       = local.name
}
