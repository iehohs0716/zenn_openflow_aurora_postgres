#!/bin/bash

# 6. DCP のブートストラップトークンを生成して、Secrets Manager のシークレットに同期するスクリプト
#
#   1. 事前チェック (Snowflake の接続情報 / terraform.tfvars の設定 / 秘密鍵)
#   2. シークレットの現在のトークンの期限を確認 (有効なら何もしない。--force で再生成)
#   3. snow sql で SYSTEM$GENERATE_DATA_CONNECTIVITY_PROXY_BOOTSTRAP_TOKEN を実行してトークンを生成
#   4. トークンを Secrets Manager に投入 (一時ファイル経由。state・コマンド引数・シェル履歴に残さない)
#
# 使い方:
#   ./scripts/6_sync_dcp_token.sh            トークンが無い / 期限切れが近いときだけ再生成する
#   ./scripts/6_sync_dcp_token.sh --force    有効なトークンがあっても再生成する
#   ./scripts/6_sync_dcp_token.sh --days 14  トークンの有効日数を指定する (既定 7、最大 90)
#
# 前提:
#   - scripts/1_deploy_network.sh でシークレットが、scripts/5_deploy_snowflake_dcp.sh で DCP オブジェクトが作成済みであること
#   - .env に Snowflake の接続情報 (SNOWFLAKE_*) を設定していること (.env.sample を参照)
#   - terraform.tfvars に snowflake_private_key_path を設定していること (provider と同じ秘密鍵を使う)
#   - snow (Snowflake CLI) と jq がインストールされていること
# 実行中のエージェントは、証明書のローテーションのたびにトークンのファイルを再読込するため、再起動は不要
# (ただし、EC2 の user_data が取得するのは起動時の値。トークンを更新した後で EC2 を作り直す場合に最新の値が使われる)

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common/setup.sh"
source "$COMMON_DIR/snowflake.sh"

check_command "terraform" "Terraformをインストールしてください: brew install terraform"
check_command "aws" "AWS CLIをインストールしてください: brew install awscli"
check_command "snow" "Snowflake CLIをインストールしてください: brew install snowflake-cli"
check_command "jq" "jqをインストールしてください: brew install jq"

# 引数の解析
FORCE=false
DAYS=7
while [ $# -gt 0 ]; do
  case "$1" in
    --force)
      FORCE=true
      shift
      ;;
    --days)
      if [ $# -lt 2 ]; then
        echo "Error: --days には日数を指定してください。"
        exit 1
      fi
      DAYS="$2"
      shift 2
      ;;
    *)
      echo "Error: 不明なオプション: $1"
      echo "Usage: $0 [--force] [--days N]"
      exit 1
      ;;
  esac
done

if ! [[ "$DAYS" =~ ^[0-9]+$ ]] || [ "$DAYS" -lt 1 ] || [ "$DAYS" -gt 90 ]; then
  echo "Error: --days は 1〜90 の整数を指定してください (指定値: $DAYS)。"
  exit 1
fi

load_env
require_snowflake_env
cd_terraform_dir

select_aws_auth
TOKEN_FILE=""
trap 'rm -f "$TOKEN_FILE"' EXIT
check_aws_credentials
terraform_init

# 設定値の取得 (シークレット名と DCP 名は main.tf / variables.tf を参照。二重管理しない)
echo "🔎 設定を確認中..."
tf_eval 'local.dcp_token_secret_name'
SECRET_NAME="$TF_RESULT"
tf_eval 'var.snowflake_dcp_name'
DCP_NAME="$TF_RESULT"
for pair in "シークレット名:$SECRET_NAME" "DCP 名:$DCP_NAME"; do
    if [ -z "${pair#*:}" ] || [[ "${pair#*:}" == *"known after apply"* ]]; then
        echo "❌ ${pair%%:*}を取得できません。terraform.tfvars を確認してください (terraform.tfvars.sample を参照)。"
        exit 1
    fi
done
resolve_snowflake_key_path
echo "📌 トークン格納先: $SECRET_NAME"
echo "📌 DCP: $DCP_NAME"
echo ""

# JWT の期限 (exp、エポック秒) をローカルで取り出す。トークンは表示しない
jwt_exp() {
    echo "$1" | cut -d. -f2 | jq -R -r \
        'gsub("-";"+") | gsub("_";"/") | . + ("=" * ((4 - (length % 4)) % 4)) | @base64d | fromjson | .exp // empty' \
        2> /dev/null || true
}

# 現在のトークンの期限を確認 (有効なら何もしない)
CURRENT_VALUE="$(run aws secretsmanager get-secret-value --region "$AWS_REGION_NAME" --secret-id "$SECRET_NAME" \
    --query SecretString --output text 2> /dev/null || true)"
if [ -z "$CURRENT_VALUE" ]; then
    echo "❌ シークレット ($SECRET_NAME) を取得できません。先に scripts/1_deploy_network.sh を実行してください。"
    exit 1
fi

if [ "$CURRENT_VALUE" != "PLACEHOLDER" ] && [ "$FORCE" = false ]; then
    CURRENT_EXP="$(jwt_exp "$CURRENT_VALUE")"
    if [[ "$CURRENT_EXP" =~ ^[0-9]+$ ]]; then
        REMAINING=$(( CURRENT_EXP - $(date +%s) ))
        if [ "$REMAINING" -gt 86400 ]; then
            echo "✅ シークレットのトークンは有効です (期限: $(jq -n -r --argjson e "$CURRENT_EXP" '$e | todate'))。何もしません。"
            echo "   再生成する場合は --force を付けてください。"
            exit 0
        fi
        echo "ℹ️  シークレットのトークンの期限が近いか、切れています。再生成します。"
    else
        echo "ℹ️  シークレットの値から期限を読み取れません。再生成します。"
    fi
fi
CURRENT_VALUE=""

# トークンを生成 (snow sql。接続設定ファイルは使わず、.env の値と provider と同じ秘密鍵で接続する)
echo "🔑 Snowflake でトークンを生成中... (有効日数: $DAYS)"
SNOW_ARGS=(--temporary-connection
    --account "${SNOWFLAKE_ORGANIZATION_NAME}-${SNOWFLAKE_ACCOUNT_NAME}"
    --user "$SNOWFLAKE_USER"
    --authenticator SNOWFLAKE_JWT
    --private-key-file "$KEY_PATH"
    --format JSON --silent)
if [ -n "${SNOWFLAKE_ROLE:-}" ]; then
    SNOW_ARGS+=(--role "$SNOWFLAKE_ROLE")
fi

if ! RESULT="$(snow sql "${SNOW_ARGS[@]}" \
    -q "SELECT SYSTEM\$GENERATE_DATA_CONNECTIVITY_PROXY_BOOTSTRAP_TOKEN('${DCP_NAME}', ${DAYS}) AS TOKEN")"; then
    echo "❌ トークンの生成に失敗しました (Snowflake への接続、DCP オブジェクトの存在、実行ロールの権限を確認してください)"
    exit 1
fi

TOKEN="$(echo "$RESULT" | jq -r '.[0].TOKEN // empty' 2> /dev/null || true)"
RESULT=""

if [ -z "$TOKEN" ]; then
    echo "❌ トークンを取得できませんでした (snow sql の出力にトークンが含まれていません)"
    exit 1
fi
if [[ "$TOKEN" == PAT_* ]]; then
    echo "❌ PAT_ で始まる値は使えません (Snowflake Access JWT が必要です)"
    exit 1
fi
NEW_EXP="$(jwt_exp "$TOKEN")"
if ! [[ "$NEW_EXP" =~ ^[0-9]+$ ]]; then
    echo "❌ 生成された値が JWT として読み取れません。Secrets Manager には投入しません。"
    exit 1
fi

# 引数 (ps に見える) ではなく、権限 600 の一時ファイル経由で渡す
umask 077
TOKEN_FILE="$(mktemp)"
printf '%s' "$TOKEN" > "$TOKEN_FILE"
TOKEN=""

run aws secretsmanager put-secret-value --region "$AWS_REGION_NAME" --secret-id "$SECRET_NAME" \
    --secret-string "file://$TOKEN_FILE" > /dev/null
rm -f "$TOKEN_FILE"
TOKEN_FILE=""

echo ""
echo "========================================="
echo "✅ トークンをシークレットに同期しました"
echo "========================================="
echo "  シークレット: $SECRET_NAME"
echo "  期限:         $(jq -n -r --argjson e "$NEW_EXP" '$e | todate')"
echo ""
echo "次のステップ: ./scripts/7_deploy_dcp_agent.sh"
echo ""
