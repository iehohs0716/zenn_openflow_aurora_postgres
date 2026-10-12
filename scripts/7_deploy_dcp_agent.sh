#!/bin/bash

# 7. DCP エージェント (EC2) を構築するスクリプト
#
#   1. terraform init
#   2. 事前チェック (トークンが Secrets Manager に同期済みか)
#   3. DCP エージェント (module.dcp_agent) だけを plan → 確認 → apply (-target)
#
# 前提:
#   - scripts/1_deploy_network.sh で VPC とシークレットが作成済みであること
#   - scripts/6_sync_dcp_token.sh でトークンがシークレットに同期済みであること
#     (未同期のまま EC2 を起動すると、user_data が 5 分待ってから失敗する)
# VPC と Aurora 本体は含めない。Aurora は scripts/2_deploy_aurora.sh で作成済みの想定
# (DCP エージェントの送信先として、Aurora の Security Group を参照する)
#

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common/setup.sh"
source "$COMMON_DIR/terraform.sh"

check_command "terraform" "Terraformをインストールしてください: brew install terraform"
check_command "aws" "AWS CLIをインストールしてください: brew install awscli"

load_env
cd_terraform_dir

select_aws_auth
trap_remove_tfplan
check_aws_credentials
terraform_init

# トークンが同期済みか確認 (シークレット名は main.tf の local を参照。値は表示しない)
echo "🔎 トークンの同期状況を確認中..."
tf_eval 'local.dcp_token_secret_name'
SECRET_NAME="$TF_RESULT"
if [ -z "$SECRET_NAME" ] || [[ "$SECRET_NAME" == *"known after apply"* ]]; then
    echo "❌ シークレット名を取得できませんでした"
    exit 1
fi

CURRENT_VALUE="$(run aws secretsmanager get-secret-value --region "$AWS_REGION_NAME" --secret-id "$SECRET_NAME" \
    --query SecretString --output text 2> /dev/null || true)"
if [ -z "$CURRENT_VALUE" ]; then
    echo "❌ シークレット ($SECRET_NAME) を取得できません。先に scripts/1_deploy_network.sh を実行してください。"
    exit 1
fi
if [ "$CURRENT_VALUE" = "PLACEHOLDER" ]; then
    echo "❌ シークレット ($SECRET_NAME) にトークンが入っていません。先に scripts/6_sync_dcp_token.sh を実行してください。"
    exit 1
fi
CURRENT_VALUE=""
echo "✅ トークンは同期済みです ($SECRET_NAME)"
echo ""

# DCP エージェントのみの plan
echo "📝 DCP エージェントの plan を確認中..."
run terraform plan -input=false -target="module.dcp_agent" -out=tfplan
echo ""

confirm_or_exit "上記の内容でリソースを作成しますか？"

echo ""
echo "🚀 リソースを作成中..."
run terraform apply tfplan
rm -f tfplan
echo ""

echo "========================================="
echo "✅ DCP エージェントの構築完了"
echo "========================================="
echo ""
echo "次のステップ: Snowflake 側の接続状態を確認してください (起動まで数分かかります)"
echo "  ./scripts/check_dcp_snowflake.sh (AGENT_HEALTH=HEALTHY / AGENT_STATUS=DCP_AGENT_LIFECYCLE_CONNECTED なら接続済み)"
echo "  EC2 側の確認: ./scripts/check_dcp_agent.sh"
echo "その後: ./scripts/8_create_openflow_runtime.sh"
echo ""
