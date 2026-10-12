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

# Openflow のコネクタ (カタログ定義から作成する)。Runtime の上で動く。
#
# コネクタのリソースは provider ではプレビュー機能のため、provider の preview_features_enabled に
# snowflake_openflow_connector_resource を指定する必要がある (infra/env/dev/backend.tf)。
#
# 作成するのはコネクタのオブジェクトだけ (STOPPED / Draft)。次は Terraform の管理外:
# - パラメータ (config.json) の設定。provider はパラメータの設定機構を持たない。Openflow の UI で設定する
# - 起動・停止・バージョン管理 (provider の公式ドキュメントで「望ましい状態ではなく運用操作」とされている)
# `from` は作成時のみ有効で、読み戻されない (外部での変更は検出されない)。
# 変更系の操作は非同期で、provider がコネクタが落ち着くまで待つ。
#
# 識別子は引用符なしで書ける名前に限定しているため、Snowflake 上では大文字になる。
# ネイティブのリソースは名前をそのまま引用符付きで扱うので、upper() で大文字にそろえる。
#
# 必要な権限 (実行ロール): スキーマの CREATE OPENFLOW CONNECTOR と、Runtime の USAGE

locals {
  database = upper(var.database)
  schema   = upper(var.schema)
  name     = upper(var.connector_name)

  runtime_database = upper(coalesce(var.runtime_database, var.database))
  runtime_schema   = upper(coalesce(var.runtime_schema, var.schema))

  # Runtime の完全修飾名 (引用符付き)
  runtime_fqn_quoted = "\"${local.runtime_database}\".\"${local.runtime_schema}\".\"${upper(var.runtime_name)}\""
}

resource "snowflake_openflow_connector" "this" {
  database = local.database
  schema   = local.schema
  name     = local.name
  runtime  = local.runtime_fqn_quoted

  from {
    definition = var.definition
  }

  display_name = var.display_name
  comment      = var.comment

  timeouts {
    create = "60m"
    update = "60m"
    delete = "60m"
  }
}
