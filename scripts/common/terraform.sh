#!/bin/bash

# Terraform まわりの共通関数。実行せず、source して使う
# 前提: common/setup.sh を source 済みであること (aws.sh はここで source する)

source "$COMMON_DIR/aws.sh"

# Terraform初期化
# state のバケット名は、.env の TF_CLI_ARGS_init (terraform init に -backend-config を足す) で渡される
terraform_init() {
  if [[ "${TF_CLI_ARGS_init:-}" != *"-backend-config="* ]]; then
    echo "❌ .env に TF_CLI_ARGS_init が設定されていません (.env.sample を参照)。"
    echo "   backend.tfbackend.sample をコピーして backend.tfbackend を作り、そのパスを指定してください。"
    exit 1
  fi
  echo "🔧 Terraform初期化中..."
  run terraform init
  echo ""
}

# 終了時に plan ファイルを削除する
trap_remove_tfplan() {
  trap 'rm -f tfplan' EXIT
}

# terraform console で式を評価して、結果を TF_RESULT に入れる (Snowflake には接続しない)。
# terraform console は、変数の validation エラーが出ても終了コードが 0 で、エラーは標準エラー出力に出る。
# そのため、終了コードではなく標準エラー出力の "Error:" で失敗を判定し、Terraform のエラーをそのまま表示して中断する。
# 未設定の必須変数は、結果が "(known after apply)" になる
#   tf_eval 'local.dcp_token_secret_name'
tf_eval() {
  local out err errfile
  errfile="$(mktemp)"
  out="$(echo "$1" | run terraform console 2> "$errfile")" || true
  err="$(cat "$errfile")"
  rm -f "$errfile"
  if echo "$err" | grep -q "Error:"; then
    echo "❌ terraform.tfvars の設定が不正です:"
    echo "$err"
    exit 1
  fi
  # 結果の行だけを取り出す (警告の枠線 ╷ │ ╵ と空行は除く)
  TF_RESULT="$(echo "$out" | grep -v -e '^╷' -e '^│' -e '^╵' -e '^$' | head -1 | tr -d '"')"
}
