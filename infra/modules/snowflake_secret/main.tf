terraform {
  required_version = ">= 1.7"
  required_providers {
    snowflake = {
      # 登録名は snowflakedb/snowflake (旧 Snowflake-Labs/snowflake は 1.0.5 で更新が止まっている)
      source  = "snowflakedb/snowflake"
      version = "~> 2.21"
    }
  }
}

# 値を Terraform 管理外にする Snowflake のシークレット (GENERIC_STRING)。
# state に秘密を載せないため、プレースホルダで作成し、実値は
# `ALTER SECRET <名前> SET SECRET_STRING = '...'` で投入する (scripts/ が行う)。
# secret_string は ignore_changes にしているため、投入した実値を Terraform が上書きしない。
#
# データベース・スキーマは既存のものを使い、作成しない (名前を引数で受ける)。
# 識別子は引用符なしで書ける名前に限定しているため、Snowflake 上では大文字になる。
# ネイティブのリソースは名前をそのまま引用符付きで扱うので、upper() で大文字にそろえる。

locals {
  database = upper(var.database)
  schema   = upper(var.schema)
  name     = upper(var.name)

  secret_fqn_quoted = "\"${local.database}\".\"${local.schema}\".\"${local.name}\""
}

resource "snowflake_secret_with_generic_string" "this" {
  database = local.database
  schema   = local.schema
  name     = local.name
  comment  = var.comment

  secret_string = "PLACEHOLDER"

  lifecycle {
    ignore_changes = [secret_string]
  }
}

# シークレットを参照するロール (Runtime の実行ロールなど) への READ 権限
resource "snowflake_grant_privileges_to_account_role" "read" {
  for_each = toset([for r in var.read_roles : upper(r)])

  account_role_name = each.value
  privileges        = ["READ"]

  on_schema_object {
    object_type = "SECRET"
    object_name = local.secret_fqn_quoted
  }

  depends_on = [snowflake_secret_with_generic_string.this]
}
