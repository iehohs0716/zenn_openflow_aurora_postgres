#!/bin/bash

# サンプルのテーブルに対して、CRUD (INSERT / UPDATE / DELETE / SELECT) を実行するスクリプト
# CDC で、変更が Snowflake に届くかを検証するための、変更を発生させる元になる
#
# 使い方:
#   ./scripts/crud_sample.sh insert [--count N] [--batch ID]   顧客と注文を N 件ずつ追加する
#   ./scripts/crud_sample.sh update [--count N] [--batch ID]   未出荷の注文を N 件進め、顧客の属性を N 件更新する
#   ./scripts/crud_sample.sh delete [--count N] [--batch ID]   出荷済みの注文と、注文のなくなった顧客を N 件ずつ削除する
#   ./scripts/crud_sample.sh select [--count N]                現在の件数と、直近の変更 N 件を表示する
#
#   --count N   件数 (既定 10、1〜100000)
#   --batch ID  この実行の識別子 (既定は実行時刻 UTC)。変更した行の last_batch_id に入り、
#               Snowflake 側で、欠落・重複・順序を実行単位で突き合わせるのに使う (英数字・_・- のみ)
#
# 前提: scripts/4_execute_sql_to_aurora.sh でサンプルデータを投入済みであること
# 手元に psql や session-manager-plugin は不要。ツールのコンテナ (data/docker-compose.yml) の中で実行する

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common/setup.sh"
source "$COMMON_DIR/db.sh"

usage() {
    sed -n '/^# 使い方:/,/^# 前提:/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'
}

if [ $# -eq 0 ]; then
    usage
    exit 1
fi

OPERATION="$1"
shift
case "$OPERATION" in
    insert | update | delete | select) ;;
    -h | --help)
        usage
        exit 0
        ;;
    *)
        echo "Error: 不明な操作: $OPERATION"
        usage
        exit 1
        ;;
esac

COUNT=10
BATCH_ID="$(date -u +%Y%m%d%H%M%S)"
while [ $# -gt 0 ]; do
    case "$1" in
        --count)
            [ $# -ge 2 ] || { echo "Error: --count には件数を指定してください。"; exit 1; }
            COUNT="$2"
            shift 2
            ;;
        --batch)
            [ $# -ge 2 ] || { echo "Error: --batch には識別子を指定してください。"; exit 1; }
            BATCH_ID="$2"
            shift 2
            ;;
        *)
            echo "Error: 不明なオプション: $1"
            exit 1
            ;;
    esac
done

if ! [[ "$COUNT" =~ ^[0-9]+$ ]] || [ "$COUNT" -lt 1 ] || [ "$COUNT" -gt 100000 ]; then
    echo "Error: --count は 1〜100000 の整数を指定してください (指定値: $COUNT)。"
    exit 1
fi
if ! [[ "$BATCH_ID" =~ ^[A-Za-z0-9_-]+$ ]]; then
    echo "Error: --batch は英数字・_・- のみ指定できます (指定値: $BATCH_ID)。"
    exit 1
fi

check_command "terraform" "Terraformをインストールしてください: brew install terraform"
check_command "aws" "AWS CLIをインストールしてください: brew install awscli"
check_command "jq" "jqをインストールしてください: brew install jq"
require_docker

load_env
cd_terraform_dir

select_aws_auth
check_aws_credentials
terraform_init
resolve_data_engine

prepare_db_env
echo ""
echo "🚀 $OPERATION を実行中... (件数: $COUNT / バッチ: $BATCH_ID)"
db_psql -v "count=$COUNT" -v "batch_id=$BATCH_ID" -f "/data/$DB_ENGINE_DIR/crud/$OPERATION.sql"
echo ""
