#!/bin/bash

# 4. サンプルのスキーマ・テーブル・初期データと、Openflow 用の設定を Aurora に投入するスクリプト
#
#   1. 事前チェック (Docker / terraform output)
#   2. Openflow 用レプリケーションユーザーのパスワードを生成してシークレットに投入 (未投入のときだけ)
#   3. data/<エンジン>/schema と seed と cdc の SQL を、この順に psql で実行する (繰り返し実行できる)
#      cdc は Openflow が変更を読み取るためのレプリケーションユーザーと publication (対象テーブルが先に必要なため schema の後)
#
# 前提:
#   - scripts/2_deploy_aurora.sh で Aurora (とパスワード用のシークレット) が、
#     scripts/3_deploy_aurora_bastion.sh で踏み台 (EC2) が作成済みであること
#   - Docker (docker compose v2) が起動していること
# 手元に psql や session-manager-plugin は不要。ツールのコンテナ (data/docker-compose.yml) の中で実行する
# 課金: 追加の課金は発生しない
# 次の作業: scripts/crud_sample.sh

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common/setup.sh"
source "$COMMON_DIR/db.sh"

check_command "terraform" "Terraformをインストールしてください: brew install terraform"
check_command "aws" "AWS CLIをインストールしてください: brew install awscli"
check_command "jq" "jqをインストールしてください: brew install jq"
check_command "openssl" "opensslをインストールしてください"
require_docker

load_env
cd_terraform_dir

select_aws_auth
check_aws_credentials
terraform_init
resolve_data_engine

# Openflow 用レプリケーションユーザーのパスワード。未投入のときだけ生成して Secrets Manager に投入する
# (引数 (ps に見える) ではなく、権限 600 の一時ファイル経由。SQL・state・ログに残さない)
tf_eval 'local.aurora_repl_secret_name'
REPL_SECRET_NAME="$TF_RESULT"
if [ -z "$REPL_SECRET_NAME" ] || [[ "$REPL_SECRET_NAME" == *"known after apply"* ]]; then
    echo "❌ レプリケーションユーザーのシークレット名を取得できません。"
    exit 1
fi
REPL_PASSWORD="$(run aws secretsmanager get-secret-value --region "$AWS_REGION_NAME" --secret-id "$REPL_SECRET_NAME" \
    --query SecretString --output text 2> /dev/null || true)"
if [ -z "$REPL_PASSWORD" ]; then
    echo "❌ シークレット ($REPL_SECRET_NAME) を取得できません。先に scripts/2_deploy_aurora.sh を実行してください。"
    exit 1
fi
NEW_PASSWORD=false
if [ "$REPL_PASSWORD" = "PLACEHOLDER" ]; then
    REPL_PASSWORD="$(openssl rand -hex 24)"
    NEW_PASSWORD=true
fi
export REPL_PASSWORD

# 実行する SQL (schema → seed → cdc の順。各ディレクトリの中は名前順)
SQL_ARGS=()
for dir in schema seed cdc; do
    for file in "$DATA_DIR/$DB_ENGINE_DIR/$dir"/*.sql; do
        if [ ! -f "$file" ]; then
            echo "❌ SQL ファイルが見つかりません: $DATA_DIR/$DB_ENGINE_DIR/$dir/"
            exit 1
        fi
        SQL_ARGS+=(-f "/data/$DB_ENGINE_DIR/$dir/$(basename "$file")")
    done
done

echo "📝 投入する SQL:"
for ((i = 1; i < ${#SQL_ARGS[@]}; i += 2)); do
    echo "  ${SQL_ARGS[$i]}"
done
echo ""

confirm_or_exit "上記の SQL を Aurora に投入しますか？"

prepare_db_env
echo ""
echo "🚀 SQL を投入中..."
db_psql "${SQL_ARGS[@]}"

# SQL が成功してから、新しく生成したパスワードをシークレットに投入する
if [ "$NEW_PASSWORD" = true ]; then
    umask 077
    PASSWORD_FILE="$(mktemp)"
    trap 'rm -f "$PASSWORD_FILE"' EXIT
    printf '%s' "$REPL_PASSWORD" > "$PASSWORD_FILE"
    run aws secretsmanager put-secret-value --region "$AWS_REGION_NAME" --secret-id "$REPL_SECRET_NAME" \
        --secret-string "file://$PASSWORD_FILE" > /dev/null
    rm -f "$PASSWORD_FILE"
fi
REPL_PASSWORD=""

echo ""
echo "========================================="
echo "✅ サンプルデータと Openflow 用の設定の投入完了"
echo "========================================="
echo "  Openflow 用ユーザー: openflow_repl (パスワード: シークレット $REPL_SECRET_NAME)"
echo "  Publication:         openflow_pub"
echo ""
echo "次のステップ: ./scripts/5_deploy_snowflake_dcp.sh (Snowflake 側の DCP オブジェクトと接続設定を作る。動作確認のデータ操作は ./scripts/crud_sample.sh でも実行できる)"
echo ""
