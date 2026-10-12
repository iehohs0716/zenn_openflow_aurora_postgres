# 出力は、値が変数だけで決まるため、depends_on でリソースへの依存を明示する。
# 依存がないと、この出力を使う側 (Runtime や権限の付与) とロールの間に順序の依存ができず、
# destroy のときにロールが先に削除されて、後続の権限の取り消しが失敗する

output "admin_role_name" {
  description = "Runtime / コネクタを操作するロール名"
  value       = var.admin_role_name

  depends_on = [
    snowflake_account_role.admin,
    snowflake_grant_privileges_to_account_role.admin_database,
    snowflake_grant_privileges_to_account_role.admin_schema,
    snowflake_grant_privileges_to_account_role.admin_openflow,
    snowflake_grant_account_role.admin_to_operator,
    snowflake_grant_account_role.runtime_to_admin,
  ]
}

output "runtime_role_name" {
  description = "Runtime の EXECUTE_AS_ROLE に指定するロール名"
  value       = var.runtime_role_name

  depends_on = [
    snowflake_account_role.runtime,
    snowflake_grant_account_role.runtime_to_admin,
    snowflake_grant_privileges_to_account_role.runtime_database,
    snowflake_grant_privileges_to_account_role.runtime_schema,
    snowflake_grant_privileges_to_account_role.runtime_warehouse,
  ]
}
