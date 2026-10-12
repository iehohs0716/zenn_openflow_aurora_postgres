#!/bin/bash

# 9. Openflow のコネクタ (オブジェクトのみ) を作成するスクリプト
#
#   1. 事前チェック (Snowflake の接続情報 / terraform.tfvars の設定 / Runtime の存在)
#   2. コネクタ (module.snowflake_openflow_connector) だけを plan → 確認 → apply (-target)
#      カタログ定義 (OPENFLOW_POSTGRES_CDC) から作成する。コネクタ名は terraform.tfvars の snowflake_openflow_connector_name
#
# 作るのはコネクタのオブジェクトだけ (STOPPED / Draft)。パラメータ (config.json) の設定と起動は Terraform の管理外で、
# Openflow の UI で行う (provider がパラメータの設定機構を持たない)。
#
# 前提:
#   - scripts/8_create_openflow_runtime.sh で Runtime が作成済みであること
#   - .env の SNOWFLAKE_ROLE が、スキーマの CREATE OPENFLOW CONNECTOR と Runtime の USAGE を持つこと
#   - terraform.tfvars に snowflake_openflow_connector_name を設定していること (terraform.tfvars.sample を参照)
# 課金: コネクタのオブジェクト自体に追加の課金はない (Runtime の課金は 9 と同じ)
# 注意: Openflow 系の Terraform リソースはプレビュー機能で、apply はコネクタが落ち着くまで待つ

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common/setup.sh"
source "$COMMON_DIR/snowflake.sh"

check_command "terraform" "Terraformをインストールしてください: brew install terraform"
check_command "aws" "AWS CLIをインストールしてください: brew install awscli"

load_env
require_snowflake_env
cd_terraform_dir

select_aws_auth
trap_remove_tfplan
check_aws_credentials
terraform_init
require_snowflake_tfvars

# Runtime が作成済みかチェック (-target は依存先も対象に含めるため、未作成だと Runtime まで作ってしまう)
if ! run terraform state list module.snowflake_openflow_runtime 2> /dev/null | grep -q "snowflake_openflow_runtime.this"; then
    echo "❌ Runtime が state にありません。先に scripts/8_create_openflow_runtime.sh を実行してください。"
    exit 1
fi
echo "✅ 事前チェックOK"
echo ""

# コネクタのみの plan (plan の時点で Snowflake に接続する)
echo "📝 コネクタの plan を確認中..."
run terraform plan -input=false -target="module.snowflake_openflow_connector" -out=tfplan
echo ""

confirm_or_exit "上記の内容でコネクタを作成しますか？"

echo ""
echo "🚀 コネクタを作成中..."
run terraform apply tfplan
rm -f tfplan
echo ""

echo "========================================="
echo "✅ コネクタの作成完了 (STOPPED / Draft)"
echo "========================================="
echo ""
# -target の apply では output が state に書かれない場合があるため、値は変数と state の既存の output から取り出す
get_tf_value() {
    tf_eval "$2"
    if [ -z "$TF_RESULT" ] || [[ "$TF_RESULT" == *"known after apply"* ]]; then
        echo "❌ $1を取得できません。terraform.tfvars を確認してください (terraform.tfvars.sample を参照)。"
        exit 1
    fi
}
get_tf_value "snowflake_database" 'var.snowflake_database'
DATABASE="$TF_RESULT"
get_tf_value "snowflake_schema" 'var.snowflake_schema'
SCHEMA="$TF_RESULT"
get_tf_value "コネクタ名" 'var.snowflake_openflow_connector_name'
CONNECTOR_NAME="$TF_RESULT"
get_tf_value "Snowflake のシークレット名" 'local.snowflake_aurora_repl_secret_name'
SECRET_NAME="$TF_RESULT"
get_tf_value "aurora_database_name" 'var.aurora_database_name'
AURORA_DB_NAME="$TF_RESULT"
get_tf_value "snowflake_warehouse" 'var.snowflake_warehouse'
WAREHOUSE="$TF_RESULT"
TARGET="$(run terraform output -raw snowflake_dcp_target 2> /dev/null || true)"
if [ -z "$TARGET" ]; then
    TARGET="<Aurora のライターエンドポイント>:<ポート>"
fi

UPPER_FQN() { echo "$1" | tr '[:lower:]' '[:upper:]'; }

echo "  コネクタ: $(UPPER_FQN "${DATABASE}.${SCHEMA}.${CONNECTOR_NAME}")"
echo ""
echo "次のステップ: Openflow の UI でコネクタのパラメータを設定して起動する。設定する値 (ウィザードのページ順):"
echo ""
echo "[Source]"
echo "  Source Database Connection URL:   jdbc:postgresql://${TARGET}/${AURORA_DB_NAME}"
echo "  Source Database Driver:           https://jdbc.postgresql.org/ からダウンロードした jar をアップロード"
echo "  Source Database User:             openflow_repl"
echo "  Source Database Password:         Snowflake のシークレット $(UPPER_FQN "${DATABASE}.${SCHEMA}.${SECRET_NAME}")"
echo "  Source Database Publication Name: openflow_pub"
echo "  Configure Logical Keys:           Default Primary Key Support"
echo ""
echo "[Replication table schema]"
echo "  Included Comma Separated Source Table Names: sample.customers,sample.orders"
echo ""
echo "[Replication columns]"
echo "  Column Filter JSON:               [] (既定のまま)"
echo ""
echo "[Destination details]"
echo "  Snowflake Destination Database:   $(UPPER_FQN "${DATABASE}")"
echo "  Snowflake Warehouse:              $(UPPER_FQN "${WAREHOUSE}")"
echo "  Destination Schema Strategy:      {database}_{schema}"
echo "  Object Identifier Resolution:     Case Insensitive"
echo "  Legacy Format Support:            Standard"
echo "  Oversized Value Strategy:         Set Null"
echo "  Error Handling Strategy:          Log Errors and Continue"
echo "  Table Storage Format:             Standard"
echo ""
echo "[Tuning]"
echo "  Merge Task Schedule CRON:         0 * * * * ?"
echo "  Concurrent Snapshot Queries:      2"
echo ""
echo "[Migration]"
echo "  Ingestion Type:                   Full"
echo "  Replication Slot Name:            (空のまま。コネクタが一意名のスロットを作る)"
echo ""
