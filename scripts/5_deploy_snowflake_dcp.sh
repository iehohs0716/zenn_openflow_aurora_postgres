#!/bin/bash

# 5. Snowflake 側の DCP 関連 (DCP オブジェクト / DCP 用の接続設定) を構築するスクリプト
#
#   1. 事前チェック (Snowflake の接続情報 / terraform.tfvars の設定 / Aurora の存在)
#   2. terraform init
#   3. DCP のモジュール (module.snowflake_dcp) だけを plan → 確認 → apply (-target)
#      DCP オブジェクト (CREATE DATA CONNECTIVITY PROXY IF NOT EXISTS <名前> ENABLED = TRUE) と、
#      DCP 用の接続設定 (ネットワークルール (MODE = DATA_CONNECTIVITY_PROXY_EGRESS) / EAI / DCP への関連付け) を、
#      snowflake_execute で作成する (EAI だけは provider のネイティブのリソース)
#
# 前提:
#   - scripts/2_deploy_aurora.sh で Aurora が作成済みであること (ライターエンドポイントをネットワークルールに登録する)
#   - .env に Snowflake の接続情報 (SNOWFLAKE_*) を設定していること (.env.sample を参照)
#   - terraform.tfvars に snowflake_private_key_path / snowflake_database / snowflake_schema を設定していること
#     (terraform.tfvars.sample を参照)
#   - 実行ロール (SNOWFLAKE_ROLE) が DCP オブジェクト・ネットワークルール・EAI を作成できること (CREATE DATA CONNECTIVITY PROXY 権限、スキーマの CREATE NETWORK RULE、アカウントの CREATE INTEGRATION など)
#   - snowflake_database / snowflake_schema の既存のものが存在すること (作成はしない)
# 課金: AWS の課金は発生しない
# 次の作業: scripts/6_sync_dcp_token.sh

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

# Aurora が作成済みかチェック (-target は依存先も対象に含めるため、未作成だと Aurora まで作ってしまう)
if ! run terraform output -raw aurora_writer_endpoint &> /dev/null; then
    echo "❌ Aurora のライターエンドポイントを state から取得できません。先に scripts/2_deploy_aurora.sh を実行してください。"
    exit 1
fi
echo "✅ 事前チェックOK"
echo ""

# Snowflake 側の設定のみの plan (plan の時点で Snowflake に接続する)
echo "📝 Snowflake 側の設定の plan を確認中..."
run terraform plan -input=false -target="module.snowflake_dcp" -out=tfplan
echo ""

confirm_or_exit "上記の内容で Snowflake の DCP オブジェクト / DCP 用の接続設定を作成しますか？"

echo ""
echo "🚀 Snowflake 側の設定を作成中..."
run terraform apply tfplan
rm -f tfplan
echo ""

echo "========================================="
echo "✅ Snowflake 側の DCP 関連の構築完了"
echo "========================================="
echo ""
run terraform output snowflake_dcp_name
run terraform output snowflake_dcp_eai_name
run terraform output snowflake_dcp_target
echo ""
echo "次のステップ: ./scripts/6_sync_dcp_token.sh (ブートストラップトークンを生成してシークレットに同期する)"
echo "  DCP エージェントが接続したら (scripts/7_deploy_dcp_agent.sh)、./scripts/check_dcp_snowflake.sh で DCP の状態を表示し、"
echo "  EXTERNAL_ACCESS_INTEGRATIONS に上記の EAI が入っていることを確認する"
echo ""
