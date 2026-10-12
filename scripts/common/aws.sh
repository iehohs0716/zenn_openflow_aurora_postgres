#!/bin/bash

# AWS 認証 (aws-vault の選択) と、aws-vault の有無に応じたコマンド実行。実行せず、source して使う
# 前提: common/setup.sh を source 済みであること

# aws-vaultの使用を確認する。USE_AWS_VAULT / AWS_VAULT_PROFILE を設定し、使わない場合は AWS_PROFILE を export する
select_aws_auth() {
  USE_AWS_VAULT=false
  if command -v aws-vault &> /dev/null; then
    echo "🔐 aws-vaultが検出されました"
    read -p "aws-vault (MFA認証) を使用しますか？ (yes/no): " use_vault
    if [ "$use_vault" = "yes" ]; then
      USE_AWS_VAULT=true
      AWS_VAULT_PROFILE="ds-sandbox-vault"
      echo "✅ aws-vaultを使用します (プロファイル: $AWS_VAULT_PROFILE)"
      echo "📱 Google Authenticatorの6桁コードが必要になります"
    fi
  else
    echo "ℹ️  aws-vaultが見つかりません。通常のAWSプロファイルを使用します"
  fi

  if [ "$USE_AWS_VAULT" = false ]; then
    export AWS_PROFILE="${AWS_PROFILE:-ds-sandbox}"
    echo "🔑 使用するAWSプロファイル: $AWS_PROFILE"
  fi
  echo ""
}

# コマンドを aws-vault の有無に応じて実行するラッパー
run() {
  if [ "$USE_AWS_VAULT" = true ]; then
    aws-vault exec "$AWS_VAULT_PROFILE" -- "$@"
  else
    "$@"
  fi
}

AWS_REGION_NAME="${AWS_REGION:-ap-northeast-1}"

# AWS認証情報を確認する
check_aws_credentials() {
  echo "📋 AWS認証情報を確認中..."
  run aws sts get-caller-identity || {
    echo "❌ AWS認証に失敗しました"
    exit 1
  }
  echo ""
}
