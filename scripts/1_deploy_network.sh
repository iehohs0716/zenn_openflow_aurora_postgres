#!/bin/bash

# 1. ネットワーク (VPC / サブネット / IGW / NAT Gateway) と、DCP トークン用のシークレット (空の入れ物) を構築するスクリプト
#
#   1. terraform init
#   2. VPC (module.vpc) とシークレット (module.dcp_token_secret) だけを plan → 確認 → apply (-target)
#      シークレットの値は Terraform 管理外。scripts/6_sync_dcp_token.sh が投入する
#
# 課金: NAT Gateway (enable_nat_gateway = true のとき) の時間課金とデータ処理料金が発生する
# 次の作業: scripts/2_deploy_aurora.sh

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

# VPC とシークレットのみの plan
echo "📝 VPC とシークレットの plan を確認中..."
run terraform plan -input=false -target="module.vpc" -target="module.dcp_token_secret" -out=tfplan
echo ""

confirm_or_exit "上記の内容で VPC とシークレットを作成しますか？ (NAT Gateway の課金が発生します)"

echo ""
echo "🚀 VPC とシークレットを作成中..."
run terraform apply tfplan
rm -f tfplan
echo ""

echo "========================================="
echo "✅ ネットワークの構築完了"
echo "========================================="
echo ""
run terraform output vpc_id
run terraform output private_subnet_ids
run terraform output dcp_bootstrap_token_secret_name
echo ""
echo "次のステップ: ./scripts/2_deploy_aurora.sh"
echo ""
