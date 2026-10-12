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

# Openflow (Aurora の変更を Snowflake に取り込む) を動かすためのロールと権限。
# データベース・スキーマ・ウェアハウスは既存のものを使い、作成しない (名前を引数で受ける)。
#
# ロールと権限 (USAGE / CREATE SCHEMA / CREATE OPENFLOW RUNTIME / CREATE OPENFLOW CONNECTOR / ウェアハウス) は
# snowflake provider のネイティブのリソースで管理する。
#
# 識別子は引用符なしで書ける名前に限定しているため、Snowflake 上で大文字になる。
# ネイティブのリソースは名前をそのまま引用符付きで扱うので、upper() で大文字にそろえる。
#
# 作らないもの (必要になった時点で別途):
# - Deployment の作成権限 (アカウント権限。Deployment は既存のものを使う想定)
# - ロールのユーザーへの付与と DEFAULT_ROLE の設定 (ACCOUNTADMIN がデフォルトロールのユーザーは Runtime にログインできないため、
#   Runtime にログインするユーザーには OPENFLOW_ADMIN をデフォルトロールにする必要がある)
# - ソース DB パスワードのシークレットへの READ 権限 (シークレットの作成後)
# - Aurora 用 EAI の USAGE 権限 (EAI の作成後)

locals {
  database  = upper(var.database)
  schema    = upper(var.schema)
  warehouse = upper(var.warehouse)

  # execute 用 (引用符なし) と、ネイティブのリソース用 (引用符付きの完全修飾名)
  schema_fqn        = "${local.database}.${local.schema}"
  schema_fqn_quoted = "\"${local.database}\".\"${local.schema}\""
}

# ---------------------------------------------
# Runtime / コネクタを操作するロール (OPENFLOW_ADMIN)
# Runtime / コネクタをスキーマに作るための権限を持つ
# ---------------------------------------------
resource "snowflake_account_role" "admin" {
  name = upper(var.admin_role_name)
}

resource "snowflake_grant_privileges_to_account_role" "admin_database" {
  account_role_name = snowflake_account_role.admin.name
  privileges        = ["USAGE"]

  on_account_object {
    object_type = "DATABASE"
    object_name = local.database
  }
}

resource "snowflake_grant_privileges_to_account_role" "admin_schema" {
  account_role_name = snowflake_account_role.admin.name
  privileges        = ["USAGE"]

  on_schema {
    schema_name = local.schema_fqn_quoted
  }
}

resource "snowflake_grant_privileges_to_account_role" "admin_openflow" {
  account_role_name = snowflake_account_role.admin.name
  privileges        = ["CREATE OPENFLOW RUNTIME", "CREATE OPENFLOW CONNECTOR"]

  on_schema {
    schema_name = local.schema_fqn_quoted
  }
}

# snowflake_execute で付与していた時の state を、REVOKE を実行せずに外す
# (revert が走ると、上のリソースが付与した権限を取り消してしまうため)
removed {
  from = snowflake_execute.admin_openflow_grants

  lifecycle {
    destroy = false
  }
}

# ---------------------------------------------
# Runtime の実行ロール (EXECUTE_AS_ROLE)
# コネクタが宛先のデータベースにスキーマ・テーブルを作り、ウェアハウスで MERGE するための権限を持つ
# ---------------------------------------------
resource "snowflake_account_role" "runtime" {
  name = upper(var.runtime_role_name)
}

# Runtime を作るロール (OPENFLOW_ADMIN) が実行ロールを使えるようにする
# (公式 Create an execute-as role: GRANT ROLE <実行ロール> TO ROLE openflow_admin)。
# これがないと CREATE OPENFLOW RUNTIME が "Insufficient privileges to operate on ROLE" で失敗する
resource "snowflake_grant_account_role" "runtime_to_admin" {
  role_name        = snowflake_account_role.runtime.name
  parent_role_name = snowflake_account_role.admin.name
}

# Terraform / スクリプトの実行ロール (.env の SNOWFLAKE_ROLE) が OPENFLOW_ADMIN の権限を使えるようにする
# (実行ロールは、自分で作ったロールを所有していても、ロールの階層に入っていないと、そのロールとして操作できない)
resource "snowflake_grant_account_role" "admin_to_operator" {
  for_each = toset([for r in var.admin_granted_to_roles : upper(r)])

  role_name        = snowflake_account_role.admin.name
  parent_role_name = each.value
}

resource "snowflake_grant_privileges_to_account_role" "runtime_database" {
  account_role_name = snowflake_account_role.runtime.name
  privileges        = ["USAGE", "CREATE SCHEMA"]

  on_account_object {
    object_type = "DATABASE"
    object_name = local.database
  }
}

# スキーマ内のシークレット (ソース DB パスワード) を参照するために必要
resource "snowflake_grant_privileges_to_account_role" "runtime_schema" {
  account_role_name = snowflake_account_role.runtime.name
  privileges        = ["USAGE"]

  on_schema {
    schema_name = local.schema_fqn_quoted
  }
}

resource "snowflake_grant_privileges_to_account_role" "runtime_warehouse" {
  account_role_name = snowflake_account_role.runtime.name
  privileges        = ["USAGE", "OPERATE"]

  on_account_object {
    object_type = "WAREHOUSE"
    object_name = local.warehouse
  }
}
