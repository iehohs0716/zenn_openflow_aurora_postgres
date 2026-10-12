#!/bin/bash

# Aurora を構築するスクリプト
#
#   1. terraform init
#   2. Aurora (module.aurora) と、Openflow 用レプリケーションユーザーのパスワードのシークレット (module.aurora_repl_secret)
#      だけを plan → 確認 → apply (-target)。シークレットの値は scripts/4_execute_sql_to_aurora.sh が投入する
#
# 前提: scripts/1_deploy_network.sh で VPC が作成済みであること
#       (Aurora の接続元として、DCP エージェントと踏み台の Security Group だけは依存関係で一緒に作られる)
# 課金: Aurora クラスタ / インスタンスの料金が発生する。検証後は scripts/destroy.sh で削除する

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

# Aurora のみの plan
echo "📝 Aurora の plan を確認中..."
run terraform plan -input=false -target="module.aurora" -target="module.aurora_repl_secret" -out=tfplan
echo ""

confirm_or_exit "上記の内容で Aurora を作成しますか？ (課金が発生します)"

echo ""
echo "🚀 Aurora を作成中... (クラスタの作成には十数分かかることがあります)"
run terraform apply tfplan
rm -f tfplan
echo ""

echo "========================================="
echo "✅ Aurora の構築完了"
echo "========================================="
echo ""
run terraform output aurora_writer_endpoint
run terraform output aurora_master_user_secret_arn
echo ""
echo "次のステップ: ./scripts/3_deploy_aurora_bastion.sh (SQL 投入の中継に使う踏み台を作る)"
echo ""
