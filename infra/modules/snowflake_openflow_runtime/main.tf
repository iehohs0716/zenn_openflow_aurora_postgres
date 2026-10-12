terraform {
  required_version = ">= 1.0"
  required_providers {
    snowflake = {
      # 登録名は snowflakedb/snowflake (旧 Snowflake-Labs/snowflake は 1.0.5 で更新が止まっている)
      source  = "snowflakedb/snowflake"
      version = "~> 2.21"
    }
  }
}

# Openflow の Deployment と Runtime。Aurora の変更 (CDC) を Snowflake に取り込むコネクタを動かす実行環境。
#
# Openflow 系のリソースは provider ではプレビュー機能のため、provider の preview_features_enabled に
# 次の機能名を指定する必要がある (infra/env/dev/backend.tf)。破壊的変更がメジャーバージョンを上げずに入りうる。
#   snowflake_openflow_deployment_snowflake_managed_resource / snowflake_openflow_runtime_resource
# 変更系の操作は非同期で、provider が完了まで待つため、apply に数分かかる。
#
# 課金: Deployment 自体には課金がない。Runtime が動いている間、SPCS のコンピュートプールの料金が発生する。
#
# 識別子は引用符なしで書ける名前に限定しているため、Snowflake 上では大文字になる。
# ネイティブのリソースは名前をそのまま引用符付きで扱うので、upper() で大文字にそろえる。

locals {
  deployment_name = upper(var.deployment_name)
  eais            = [for e in var.external_access_integrations : upper(e)]
}

resource "snowflake_openflow_deployment_snowflake_managed" "this" {
  name = local.deployment_name

  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }
}

# コネクタが Aurora に接続するための EAI (DCP 経由) を、Runtime の実行ロールが使えるようにする
resource "snowflake_grant_privileges_to_account_role" "eai_usage" {
  for_each = toset(local.eais)

  account_role_name = upper(var.execute_as_role)
  privileges        = ["USAGE"]

  on_account_object {
    object_type = "INTEGRATION"
    object_name = each.value
  }
}

resource "snowflake_openflow_runtime" "this" {
  database        = upper(var.database)
  schema          = upper(var.schema)
  name            = upper(var.runtime_name)
  deployment      = snowflake_openflow_deployment_snowflake_managed.this.name
  node_type       = var.node_type
  min_nodes       = var.min_nodes
  max_nodes       = var.max_nodes
  execute_as_role = upper(var.execute_as_role)

  # Aurora に到達するための DCP 用 EAI
  external_access_integrations = local.eais

  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }

  depends_on = [snowflake_grant_privileges_to_account_role.eai_usage]
}
