#!/bin/bash

# 3. 踏み台 (EC2) を構築するスクリプト
#
#   1. terraform init
#   2. 事前チェック (Aurora が作成済みか)
#   3. 踏み台 (module.bastion) だけを plan → 確認 → apply (-target)
#
# 踏み台は DCP エージェントとは独立した EC2。scripts/4_execute_sql_to_aurora.sh と scripts/crud_sample.sh が、
# SSM ポートフォワーディングで Aurora に届くための中継にだけ使う (インバウンドなし、SSM Session Manager のみ)。
#
# 前提: scripts/2_deploy_aurora.sh で Aurora が作成済みであること (踏み台の送信先として Aurora の SG を参照する)
# 課金: t3.micro 1 台分の EC2 料金が発生する (外向きの通信は既存の NAT Gateway を使う)。検証後は scripts/destroy.sh で削除する

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

# Aurora が作成済みかチェック (-target は依存先も対象に含めるため、未作成だと Aurora まで作ってしまう)
if ! run terraform output -raw aurora_writer_endpoint &> /dev/null; then
    echo "❌ Aurora のライターエンドポイントを state から取得できません。先に scripts/2_deploy_aurora.sh を実行してください。"
    exit 1
fi
echo "✅ 事前チェックOK"
echo ""

# 踏み台のみの plan
echo "📝 踏み台の plan を確認中..."
run terraform plan -input=false -target="module.bastion" -out=tfplan
echo ""

confirm_or_exit "上記の内容でリソースを作成しますか？"

echo ""
echo "🚀 リソースを作成中..."
run terraform apply tfplan
rm -f tfplan
echo ""

echo "========================================="
echo "✅ 踏み台の構築完了"
echo "========================================="
echo ""
run terraform output bastion_instance_id
echo ""
echo "次のステップ: ./scripts/4_execute_sql_to_aurora.sh (SSM に登録されるまで数分かかることがある)"
echo ""
