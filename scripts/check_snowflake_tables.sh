#!/bin/bash

# Openflow が Snowflake に作った宛先テーブルの中身を確認するスクリプト (読み取りのみ)
#
#   2 つのテーブル (customers / orders) に対して SELECT * を実行し、SQL の全文と結果を表形式のまま表示する
#
# 使い方:
#   ./scripts/check_snowflake_tables.sh
#
# 宛先のテーブル名は、コネクタの設定 (scripts/9_create_openflow_connector.sh が表示する値) から決まる
#   データベース: terraform.tfvars の snowflake_database
#   スキーマ:     {ソースのデータベース名}_{ソースのスキーマ名} (Destination Schema Strategy: {database}_{schema})
#   テーブル:     ソースのテーブル名 (sample.customers / sample.orders)
# Object Identifier Resolution が Case Insensitive のため、名前は大文字になる
#
# 前提:
#   - コネクタを起動済みで、初回スナップショットが終わっていること (テーブルは取り込み後に作られる)
#   - .env に Snowflake の接続情報 (SNOWFLAKE_*) を設定していること (.env.sample を参照)
#   - terraform.tfvars に snowflake_private_key_path / snowflake_warehouse を設定していること
#   - snow (Snowflake CLI) がインストールされていること

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common/setup.sh"
source "$COMMON_DIR/snowflake.sh"

check_command "terraform" "Terraformをインストールしてください: brew install terraform"
check_command "snow" "Snowflake CLIをインストールしてください: brew install snowflake-cli"

SOURCE_SCHEMA="sample"
SOURCE_TABLES=("customers" "orders")

load_env
require_snowflake_env
cd_terraform_dir

select_aws_auth
terraform_init

get_tf_value() {
    tf_eval "$2"
    if [ -z "$TF_RESULT" ] || [[ "$TF_RESULT" == *"known after apply"* ]]; then
        echo "❌ $1を取得できません。terraform.tfvars を確認してください (terraform.tfvars.sample を参照)。"
        exit 1
    fi
}
get_tf_value "snowflake_database" 'var.snowflake_database'
DATABASE="$TF_RESULT"
get_tf_value "aurora_database_name" 'var.aurora_database_name'
AURORA_DB_NAME="$TF_RESULT"
get_tf_value "snowflake_warehouse" 'var.snowflake_warehouse'
WAREHOUSE="$TF_RESULT"
resolve_snowflake_key_path

DEST_SCHEMA="$(echo "${AURORA_DB_NAME}_${SOURCE_SCHEMA}" | tr '[:lower:]' '[:upper:]')"
DATABASE="$(echo "$DATABASE" | tr '[:lower:]' '[:upper:]')"
WAREHOUSE="$(echo "$WAREHOUSE" | tr '[:lower:]' '[:upper:]')"
echo "📌 宛先: ${DATABASE}.${DEST_SCHEMA}"
echo ""

SNOW_ARGS=(--temporary-connection
    --account "${SNOWFLAKE_ORGANIZATION_NAME}-${SNOWFLAKE_ACCOUNT_NAME}"
    --user "$SNOWFLAKE_USER"
    --authenticator SNOWFLAKE_JWT
    --private-key-file "$KEY_PATH"
    --warehouse "$WAREHOUSE"
    --silent)
if [ -n "${SNOWFLAKE_ROLE:-}" ]; then
    SNOW_ARGS+=(--role "$SNOWFLAKE_ROLE")
fi

FAILED=0
for TABLE in "${SOURCE_TABLES[@]}"; do
    SQL="SELECT * FROM ${DATABASE}.${DEST_SCHEMA}.$(echo "$TABLE" | tr '[:lower:]' '[:upper:]')"
    echo "========================================="
    echo "📋 $TABLE"
    echo "========================================="
    echo "SQL: ${SQL}"
    echo ""
    if ! snow sql "${SNOW_ARGS[@]}" -q "$SQL"; then
        echo "❌ 実行に失敗しました (テーブルが未作成か、実行ロールの権限が足りない可能性があります)"
        FAILED=1
    fi
    echo ""
done

echo "========================================="
if [ "$FAILED" -eq 0 ]; then
    echo "✅ 確認完了"
else
    echo "⚠️  確認できなかったテーブルがあります。コネクタが起動して初回スナップショットが終わっているか、"
    echo "   Snowsight で ${DATABASE}.${DEST_SCHEMA} のスキーマ名・テーブル名を確認してください"
fi
echo "========================================="
