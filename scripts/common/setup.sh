#!/bin/bash

# 全スクリプトで共通の初期化と関数。実行せず、各スクリプトの先頭で source して使う
#   source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common/setup.sh"

# 文字コード設定
export LANG=ja_JP.UTF-8
export LC_ALL=ja_JP.UTF-8

set -euo pipefail

# common/ のディレクトリ、scripts/ のディレクトリ、プロジェクトのルート
COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT_DIR="$(cd "$COMMON_DIR/.." && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 必須ツールのチェック関数
check_command() {
  if ! command -v "$1" &> /dev/null; then
    echo "Error: $1 コマンドが見つかりません。"
    echo "$2"
    exit 1
  fi
}

# .envファイルから環境変数を読み込む
load_env() {
  if [ -f "$PROJECT_ROOT/.env" ]; then
    set -a
    source "$PROJECT_ROOT/.env"
    set +a
  else
    echo "Error: .envファイルが見つかりません。.env.sampleを参考に.envファイルを作成してください。"
    exit 1
  fi
}

# Terraform のルートモジュールへ移動
cd_terraform_dir() {
  cd "$PROJECT_ROOT/infra/env/dev"
}

# 確認プロンプト。yes 以外ならキャンセルして正常終了する
#   confirm_or_exit "上記の内容でリソースを作成しますか？"
confirm_or_exit() {
  local response
  read -p "$1 (yes/no): " response
  if [ "$response" != "yes" ]; then
    echo "❌ キャンセルしました"
    exit 0
  fi
}
