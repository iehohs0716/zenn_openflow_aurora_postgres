#!/bin/bash

# 全リソースを削除するスクリプト (terraform destroy 自体が確認プロンプトを表示する)
# 対象指定なしの destroy のため、Snowflake の接続情報 (.env の SNOWFLAKE_*) と、
# terraform.tfvars の snowflake_private_key_path が必要

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common/setup.sh"
source "$COMMON_DIR/terraform.sh"

echo "========================================="
echo "環境変数読み込み"
echo "========================================="
echo ""

load_env

echo "========================================="
echo "リソース 削除"
echo "========================================="
echo ""

cd_terraform_dir

select_aws_auth
check_aws_credentials
terraform_init

# Terraform destroyの実行 (terraform destroy 自体が確認プロンプトを表示する)
echo "📝 Terraformリソースを削除します..."
run terraform destroy
echo ""

echo "========================================="
echo "✅ 削除処理が完了しました"
echo "========================================="
echo ""
