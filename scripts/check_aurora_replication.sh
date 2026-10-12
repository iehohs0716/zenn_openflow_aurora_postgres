#!/bin/bash

# Aurora のレプリケーションスロットの状態を確認するスクリプト (読み取りのみ。ツールのコンテナ経由)
#
#   data/<エンジン>/check/replication_slots.sql を実行し、SQL の全文と結果を表示する
#   スロットがあって active が t なら、Openflow のコネクタは Aurora にレプリケーションで接続できている
#
# 使い方:
#   ./scripts/check_aurora_replication.sh
#
# 前提: scripts/4_execute_sql_to_aurora.sh と同じ (踏み台 / Aurora が作成済みで、Docker が使えること)

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common/setup.sh"
source "$COMMON_DIR/db.sh"

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
echo "🔎 レプリケーションスロットを確認中..."
# -a で、実行する SQL の全文もログに出す
db_psql -a -f "/data/$DB_ENGINE_DIR/check/replication_slots.sql"
echo ""
echo "========================================="
echo "スロットがあって active が t なら、コネクタは Aurora に接続できています。"
echo "行がなければ、コネクタはまだレプリケーションを始められていません (Openflow の UI でコネクタの状態とバルチンを確認してください)"
echo "========================================="
