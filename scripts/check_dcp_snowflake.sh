#!/bin/bash

# Snowflake 側の DCP の状態を確認するスクリプト (読み取りのみ。こちらが正)
#
#   DESCRIBE DATA CONNECTIVITY PROXY <dcp名> を snow sql で実行して、
#   結果を表形式のまま表示する (AGENT_HEALTH / AGENT_STATUS / EXTERNAL_ACCESS_INTEGRATIONS など)
#   → AGENT_HEALTH=HEALTHY / AGENT_STATUS=DCP_AGENT_LIFECYCLE_CONNECTED なら、エージェントは接続できている
#
# 使い方:
#   ./scripts/check_dcp_snowflake.sh
#
# 前提:
#   - scripts/5_deploy_snowflake_dcp.sh で DCP オブジェクトが作成済みであること
#   - .env に Snowflake の接続情報 (SNOWFLAKE_*) を設定していること (.env.sample を参照)
#   - terraform.tfvars に snowflake_private_key_path を設定していること
#   - snow (Snowflake CLI) がインストールされていること
# EC2 側の状態は ./scripts/check_dcp_agent.sh で確認する

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common/setup.sh"
source "$COMMON_DIR/snowflake.sh"

check_command "terraform" "Terraformをインストールしてください: brew install terraform"
check_command "snow" "Snowflake CLIをインストールしてください: brew install snowflake-cli"

load_env
require_snowflake_env
cd_terraform_dir

# tf_eval に必要な terraform init は、AWS の認証が要る (backend が S3) ため aws-vault の選択を通す
select_aws_auth
terraform_init

tf_eval 'var.snowflake_dcp_name'
DCP_NAME="$TF_RESULT"
if [ -z "$DCP_NAME" ] || [[ "$DCP_NAME" == *"known after apply"* ]]; then
    echo "❌ DCP 名を取得できません。terraform.tfvars を確認してください (terraform.tfvars.sample を参照)。"
    exit 1
fi
resolve_snowflake_key_path
echo "📌 DCP: $DCP_NAME"
echo ""

SNOW_ARGS=(--temporary-connection
    --account "${SNOWFLAKE_ORGANIZATION_NAME}-${SNOWFLAKE_ACCOUNT_NAME}"
    --user "$SNOWFLAKE_USER"
    --authenticator SNOWFLAKE_JWT
    --private-key-file "$KEY_PATH"
    --silent)
if [ -n "${SNOWFLAKE_ROLE:-}" ]; then
    SNOW_ARGS+=(--role "$SNOWFLAKE_ROLE")
fi

echo "🔎 DESCRIBE DATA CONNECTIVITY PROXY を実行中..."
if ! snow sql "${SNOW_ARGS[@]}" -q "DESCRIBE DATA CONNECTIVITY PROXY ${DCP_NAME}"; then
    echo "❌ DESCRIBE に失敗しました (Snowflake への接続、DCP オブジェクトの存在、実行ロールの権限を確認してください)"
    exit 1
fi

echo ""
echo "========================================="
echo "AGENT_HEALTH=HEALTHY / AGENT_STATUS=DCP_AGENT_LIFECYCLE_CONNECTED なら、エージェントは接続できています"
echo "起動まで数分かかります。続く場合は ./scripts/check_dcp_agent.sh で EC2 側を確認してください"
echo "========================================="
