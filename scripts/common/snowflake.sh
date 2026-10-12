#!/bin/bash

# Snowflake の接続情報と設定の事前チェック。実行せず、source して使う
# 前提: common/setup.sh を source 済みであること (terraform.sh はここで source する)

source "$COMMON_DIR/terraform.sh"

# Snowflake の接続情報 (.env) のチェック。値は表示しない
require_snowflake_env() {
  local var
  for var in SNOWFLAKE_ORGANIZATION_NAME SNOWFLAKE_ACCOUNT_NAME SNOWFLAKE_USER; do
    if [ -z "${!var:-}" ]; then
      echo "Error: $var が設定されていません。.envに設定してください (.env.sampleを参照)。"
      exit 1
    fi
  done
}

# 秘密鍵のパスを terraform.tfvars から取得して KEY_PATH に入れる。ファイルの存在も確認する
resolve_snowflake_key_path() {
  tf_eval 'pathexpand(var.snowflake_private_key_path)'
  KEY_PATH="$TF_RESULT"
  if [ -z "$KEY_PATH" ] || [[ "$KEY_PATH" == *"known after apply"* ]]; then
    echo "❌ snowflake_private_key_path が設定されていません。terraform.tfvars に設定してください (terraform.tfvars.sample を参照)。"
    exit 1
  fi
  if [ ! -f "$KEY_PATH" ]; then
    echo "❌ 秘密鍵のファイルが見つかりません: $KEY_PATH"
    exit 1
  fi
}

# terraform.tfvars の Snowflake 関連の設定 (database / schema / 秘密鍵) をチェックする
require_snowflake_tfvars() {
  local var
  echo "🔎 terraform.tfvars の設定を確認中..."
  for var in snowflake_database snowflake_schema; do
    tf_eval "var.$var"
    if [ -z "$TF_RESULT" ] || [[ "$TF_RESULT" == *"known after apply"* ]]; then
      echo "❌ $var が設定されていません。terraform.tfvars に設定してください (terraform.tfvars.sample を参照)。"
      exit 1
    fi
  done
  resolve_snowflake_key_path
}
