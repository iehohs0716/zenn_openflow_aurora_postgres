#!/bin/bash

# コンテナの中で動くスクリプト
#   1. SSM のポートフォワーディングで、踏み台 (aws_bastion の EC2) 経由で Aurora への経路を張る (コンテナ内の localhost のみ)
#   2. Secrets Manager から DB の接続情報を取得する
#   3. 渡された引数をそのまま psql に渡して実行する
#   4. 終了時に経路を閉じる
#
# 使い方 (scripts/common/db.sh が呼ぶ):
#   run.sh -v count=10 -f /data/postgres/crud/insert.sql
#
# 必要な環境変数: TARGET_INSTANCE_ID / DB_HOST / DB_PORT / DB_NAME / DB_SECRET_ARN / AWS_REGION と AWS の認証情報

set -euo pipefail

for var in TARGET_INSTANCE_ID DB_HOST DB_PORT DB_NAME DB_SECRET_ARN AWS_REGION; do
  if [ -z "${!var:-}" ]; then
    echo "Error: 環境変数 $var が設定されていません。" >&2
    exit 1
  fi
done

# リモートのRDSに接続する用のポート
LOCAL_PORT=15432
TUNNEL_LOG="$(mktemp)"

echo "🔌 SSM ポートフォワーディングを開始します (${TARGET_INSTANCE_ID} 経由で ${DB_HOST}:${DB_PORT})..." >&2
aws ssm start-session \
  --target "$TARGET_INSTANCE_ID" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"${DB_HOST}\"],\"portNumber\":[\"${DB_PORT}\"],\"localPortNumber\":[\"${LOCAL_PORT}\"]}" \
  > "$TUNNEL_LOG" 2>&1 &
TUNNEL_PID=$!

cleanup() {
  kill "$TUNNEL_PID" 2> /dev/null || true
  rm -f "$TUNNEL_LOG"
}
trap cleanup EXIT

# ローカルのポートが開くまで待つ (最大 30 秒)
READY=false
for _ in $(seq 1 30); do
  if (exec 3<> "/dev/tcp/127.0.0.1/${LOCAL_PORT}") 2> /dev/null; then
    READY=true
    break
  fi
  if ! kill -0 "$TUNNEL_PID" 2> /dev/null; then
    break
  fi
  sleep 1
done

if [ "$READY" != true ]; then
  echo "❌ SSM のポートフォワーディングを開始できませんでした:" >&2
  cat "$TUNNEL_LOG" >&2
  echo "   確認: 踏み台の EC2 が SSM に接続できているか (AWS コンソールの Fleet Manager など)、IAM に ssm:StartSession の権限があるか" >&2
  exit 1
fi
echo "✅ 経路を確立しました (localhost:${LOCAL_PORT})" >&2

# DB の接続情報 (マスターシークレット) を取得する。パスワードは環境変数 PGPASSWORD だけで渡す
SECRET_JSON="$(aws secretsmanager get-secret-value --region "$AWS_REGION" --secret-id "$DB_SECRET_ARN" \
  --query SecretString --output text)"
DB_USER="$(echo "$SECRET_JSON" | jq -r '.username')"
export PGPASSWORD="$(echo "$SECRET_JSON" | jq -r '.password')"
SECRET_JSON=""

export PGCONNECT_TIMEOUT=10
psql -h 127.0.0.1 -p "$LOCAL_PORT" -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 "$@"
