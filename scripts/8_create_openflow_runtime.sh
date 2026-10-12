#!/bin/bash

# 8. Openflow の Deployment と Runtime を作成し、コネクタが Aurora に接続するための準備をするスクリプト
#
#   1. 事前チェック (Snowflake の接続情報 / terraform.tfvars の設定 / Aurora のパスワード / DCP 用 EAI)
#   2. Openflow 用のロール (module.snowflake_openflow_roles)、Snowflake のシークレット (module.snowflake_aurora_repl_secret)、
#      Deployment と Runtime (module.snowflake_openflow_runtime) を 1 回の plan → 確認 → apply で作成する (-target)
#      ロール (OPENFLOW_ADMIN / Runtime の実行ロール) の作成と、既存の DB・スキーマ・ウェアハウスへの権限付与は roles、
#      DCP 用 EAI の付与と、実行ロールへの EAI の USAGE 付与は runtime のモジュールで行う
#   3. ソース DB (openflow_repl) のパスワードを、Snowflake のシークレットに設定する
#      シークレットの作成と、実行ロールへの READ の付与は、手順 2 の Terraform (module.snowflake_aurora_repl_secret) が行う。
#      ここでは値の更新 (ALTER SECRET) だけを snow sql で行う。
#      パスワードは Secrets Manager から取得する。値を Terraform の state に残さないため (一時ファイル経由。引数・ログに残さない)
#
# 前提:
#   - scripts/5_deploy_snowflake_dcp.sh で EAI が作成済みであること
#   - scripts/4_execute_sql_to_aurora.sh でレプリケーションユーザーのパスワードがシークレットに投入済みであること
#   - .env の SNOWFLAKE_ROLE が、ロールの作成と権限の付与 (CREATE ROLE / MANAGE GRANTS)、Deployment / Runtime の作成、スキーマの CREATE SECRET の権限を持つこと
#   - snowflake_database / snowflake_schema / snowflake_warehouse の既存のものが存在すること (作成はしない)
#   - snow (Snowflake CLI) と jq がインストールされていること
# 課金: Deployment 自体に課金はない。Runtime が動いている間、SPCS のコンピュートプールの料金が発生する。使わないときは Runtime を SUSPEND する
# 注意: Openflow 系の Terraform リソースはプレビュー機能で、apply に数分かかる
# 次の作業: scripts/9_create_openflow_connector.sh

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common/setup.sh"
source "$COMMON_DIR/snowflake.sh"

check_command "terraform" "Terraformをインストールしてください: brew install terraform"
check_command "aws" "AWS CLIをインストールしてください: brew install awscli"
check_command "snow" "Snowflake CLIをインストールしてください: brew install snowflake-cli"

load_env
require_snowflake_env
cd_terraform_dir

select_aws_auth
trap_remove_tfplan
check_aws_credentials
terraform_init
require_snowflake_tfvars

# 設定値の取得 (名前は main.tf / variables.tf を参照。二重管理しない)
echo "🔎 設定を確認中..."
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
get_tf_value "実行ロール名" 'var.snowflake_openflow_runtime_role'
RUNTIME_ROLE="$TF_RESULT"
get_tf_value "repl シークレット名" 'local.aurora_repl_secret_name'
REPL_SECRET_NAME="$TF_RESULT"
get_tf_value "Snowflake のシークレット名" 'local.snowflake_aurora_repl_secret_name'
SOURCE_SECRET_NAME="$TF_RESULT"

# EAI と接続先は、scripts/6 で作成した後でないと Runtime に付与できない
if ! TARGET="$(run terraform output -raw snowflake_dcp_target 2> /dev/null)" || [ -z "$TARGET" ]; then
    echo "❌ DCP 用 EAI と接続先を state から取得できません。先に scripts/5_deploy_snowflake_dcp.sh を実行してください。"
    exit 1
fi

REPL_PASSWORD="$(run aws secretsmanager get-secret-value --region "$AWS_REGION_NAME" --secret-id "$REPL_SECRET_NAME" \
    --query SecretString --output text 2> /dev/null || true)"
if [ -z "$REPL_PASSWORD" ] || [ "$REPL_PASSWORD" = "PLACEHOLDER" ]; then
    echo "❌ レプリケーションユーザーのパスワードが投入されていません。先に scripts/4_execute_sql_to_aurora.sh を実行してください。"
    exit 1
fi
if ! [[ "$REPL_PASSWORD" =~ ^[A-Za-z0-9]+$ ]]; then
    echo "❌ パスワードに英数字以外が含まれています (SQL に埋め込むため、英数字のみを想定しています)。"
    exit 1
fi
REPL_PASSWORD=""

resolve_snowflake_key_path
echo "✅ 事前チェックOK"
echo ""

# ロールと Deployment と Runtime のみの plan (plan の時点で Snowflake に接続する)
echo "📝 ロールとシークレットと Deployment と Runtime の plan を確認中..."
run terraform plan -input=false -target="module.snowflake_openflow_roles" -target="module.snowflake_aurora_repl_secret" -target="module.snowflake_openflow_runtime" -out=tfplan
echo ""

confirm_or_exit "上記の内容でロールとシークレットと Deployment と Runtime を作成しますか？ (Runtime の課金が発生します。数分かかります)"

echo ""
echo "🚀 ロールとシークレットと Deployment と Runtime を作成中... (provider が完了まで待つため、数分かかります)"
run terraform apply tfplan
rm -f tfplan
echo ""

# ソース DB のパスワードをシークレットに設定する (作成と READ の付与は Terraform)。
# パスワードは再取得し、権限 600 の一時ファイルに書いて snow sql に渡す
SQL_FILE=""
trap 'rm -f "$SQL_FILE" tfplan' EXIT
FQN_SECRET="${DATABASE}.${SCHEMA}.${SOURCE_SECRET_NAME}"

echo "🔑 ソース DB のパスワードを Snowflake のシークレット ($FQN_SECRET) に設定中..."
umask 077
SQL_FILE="$(mktemp)"
REPL_PASSWORD="$(run aws secretsmanager get-secret-value --region "$AWS_REGION_NAME" --secret-id "$REPL_SECRET_NAME" \
    --query SecretString --output text)"
cat > "$SQL_FILE" << SQL
ALTER SECRET ${FQN_SECRET} SET SECRET_STRING = '${REPL_PASSWORD}';
SQL
REPL_PASSWORD=""

SNOW_ARGS=(--temporary-connection
    --account "${SNOWFLAKE_ORGANIZATION_NAME}-${SNOWFLAKE_ACCOUNT_NAME}"
    --user "$SNOWFLAKE_USER"
    --authenticator SNOWFLAKE_JWT
    --private-key-file "$KEY_PATH")
if [ -n "${SNOWFLAKE_ROLE:-}" ]; then
    SNOW_ARGS+=(--role "$SNOWFLAKE_ROLE")
fi

if ! snow sql "${SNOW_ARGS[@]}" -f "$SQL_FILE" > /dev/null; then
    echo "❌ シークレットの値の設定に失敗しました (Snowflake への接続と、シークレットの存在 (Terraform の apply が成功したか) を確認してください)"
    exit 1
fi
rm -f "$SQL_FILE"
SQL_FILE=""

echo ""
echo "========================================="
echo "✅ Deployment / Runtime / シークレットの作成完了"
echo "========================================="
echo ""
echo "次のステップ: ./scripts/9_create_openflow_connector.sh (コネクタを作成する。UI に設定する値はそこで表示する)"
echo ""
