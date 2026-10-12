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

# Snowflake の DCP (Data Connectivity Proxy) と、DCP 経由で Aurora に到達するための Snowflake 側の設定
# (公式 Set up Data Connectivity Proxy の Step 1 / Step 6 / Step 7)
#
# 注意:
# - execute を変更するとリソースが再作成される (revert → execute の順に実行)
# - DCP / ネットワークルールは CREATE OR REPLACE ではなく IF NOT EXISTS を使う
#   (OR REPLACE は Openflow ランタイムとの関連付けが外れるため)

locals {
  rule_fqn = "${var.database}.${var.schema}.${var.network_rule_name}"
  # ネイティブのリソース (EAI) に渡す、ネットワークルールの引用符付きの完全修飾名
  rule_fqn_quoted = "\"${upper(var.database)}\".\"${upper(var.schema)}\".\"${upper(var.network_rule_name)}\""
  target          = "${var.target_host}:${var.target_port}"
}

# ---------------------------------------------
# Step 1: DCP オブジェクト
# ---------------------------------------------
resource "snowflake_execute" "dcp" {
  execute = "CREATE DATA CONNECTIVITY PROXY IF NOT EXISTS ${var.name} ENABLED = TRUE"
  revert  = "DROP DATA CONNECTIVITY PROXY IF EXISTS ${var.name}"
}

# ---------------------------------------------
# Step 6: DCP 用ネットワークルール
# MODE = DATA_CONNECTIVITY_PROXY_EGRESS がプロバイダのバージョン(snowflakedb/snowflake/v2.21に対応していなかったのでsnowflake_executeを利用)
# ---------------------------------------------
resource "snowflake_execute" "network_rule" {
  execute = <<-SQL
    CREATE NETWORK RULE IF NOT EXISTS ${local.rule_fqn}
      MODE = DATA_CONNECTIVITY_PROXY_EGRESS
      TYPE = HOST_PORT
      VALUE_LIST = ('${local.target}')
  SQL
  revert  = "DROP NETWORK RULE IF EXISTS ${local.rule_fqn}"
}

# ---------------------------------------------
# Step 7 (前半): EAI の作成
# EAI は provider のネイティブのリソースで作る (ネットワークルールだけが DCP 用のモードに未対応)。
# ネイティブのリソースは名前をそのまま引用符付きで扱うので、upper() で大文字にそろえる
# (snowflake_execute で作ったルールは、引用符なしの名前なので大文字になる)
# このリソースは provider ではプレビュー機能のため、preview_features_enabled に
# snowflake_external_access_integration_resource を指定する必要がある (infra/env/dev/backend.tf)
# ---------------------------------------------
resource "snowflake_external_access_integration" "eai" {
  name    = upper(var.eai_name)
  enabled = true

  allowed_network_rules = [local.rule_fqn_quoted]

  depends_on = [snowflake_execute.network_rule]
}

# ---------------------------------------------
# Step 7 (後半): EAI を DCP オブジェクトに関連付ける
# ---------------------------------------------
resource "snowflake_execute" "dcp_association" {
  execute = "ALTER DATA CONNECTIVITY PROXY ${var.name} SET EXTERNAL_ACCESS_INTEGRATIONS = (${var.eai_name})"
  revert  = "ALTER DATA CONNECTIVITY PROXY ${var.name} UNSET EXTERNAL_ACCESS_INTEGRATIONS"

  depends_on = [snowflake_execute.dcp, snowflake_external_access_integration.eai]
}
