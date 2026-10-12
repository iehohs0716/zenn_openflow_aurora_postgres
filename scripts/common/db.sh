#!/bin/bash

# Aurora への SQL の実行。SSM ポートフォワーディングと psql は、ツールのコンテナ (data/docker-compose.yml) の中で実行する。
# 手元に psql や session-manager-plugin は不要。実行せず、source して使う
# 前提: common/setup.sh を source 済みであること (terraform.sh はここで source する)

source "$COMMON_DIR/terraform.sh"

DATA_DIR="$PROJECT_ROOT/data"
DB_COMPOSE_FILE="$DATA_DIR/docker-compose.yml"
DB_TOOLS_IMAGE="openflow-aurora-data-tools:local"

# Docker (docker compose v2) が使えることを確認する
require_docker() {
  check_command "docker" "Docker をインストールして起動してください (Docker Desktop / Rancher Desktop など)"
  if ! docker compose version &> /dev/null; then
    echo "Error: docker compose (v2) が使えません。"
    exit 1
  fi
  if ! docker info &> /dev/null; then
    echo "Error: Docker のデーモンに接続できません。Docker を起動してください。"
    exit 1
  fi
}

# Aurora のエンジンに対応する data/ 配下のディレクトリ名を DB_ENGINE_DIR に入れる
resolve_data_engine() {
  tf_eval 'var.aurora_engine'
  case "$TF_RESULT" in
    aurora-postgresql)
      DB_ENGINE_DIR="postgres"
      ;;
    *)
      echo "❌ このエンジン ($TF_RESULT) のサンプルデータは未対応です (data/ 配下にエンジン別のディレクトリが必要です)。"
      exit 1
      ;;
  esac
}

# 接続先と認証情報を環境変数に入れる (コンテナへそのまま渡される)
prepare_db_env() {
  if ! TARGET_INSTANCE_ID="$(run terraform output -raw bastion_instance_id 2> /dev/null)" || [ -z "$TARGET_INSTANCE_ID" ]; then
    echo "❌ 踏み台の EC2 がありません。先に scripts/3_deploy_aurora_bastion.sh を実行してください。"
    exit 1
  fi

  if ! DB_HOST="$(run terraform output -raw aurora_writer_endpoint 2> /dev/null)" || [ -z "$DB_HOST" ]; then
    echo "❌ Aurora のライターエンドポイントを取得できません。先に scripts/2_deploy_aurora.sh を実行してください。"
    exit 1
  fi
  DB_SECRET_ARN="$(run terraform output -raw aurora_master_user_secret_arn)"

  tf_eval 'var.db_port'
  DB_PORT="$TF_RESULT"
  tf_eval 'var.aurora_database_name'
  DB_NAME="$TF_RESULT"

  # aws-vault を使わない場合は、プロファイルの認証情報を環境変数に取り出す
  # (aws-vault を使う場合は、run が aws-vault exec で環境変数に入れる)
  if [ "$USE_AWS_VAULT" = false ]; then
    local creds
    if ! creds="$(aws configure export-credentials --profile "$AWS_PROFILE" --format env)"; then
      echo "❌ AWS の認証情報を取り出せませんでした (profile: $AWS_PROFILE)"
      exit 1
    fi
    eval "$creds"
  fi

  export AWS_REGION="$AWS_REGION_NAME"
  export TARGET_INSTANCE_ID DB_HOST DB_PORT DB_NAME DB_SECRET_ARN
}

# ツールのコンテナのイメージがなければビルドする
build_db_tools_image() {
  if ! docker image inspect "$DB_TOOLS_IMAGE" &> /dev/null; then
    echo "🔨 ツールのコンテナのイメージをビルドします (初回のみ。数分かかることがあります)..."
    docker compose -f "$DB_COMPOSE_FILE" build tools
    echo ""
  fi
}

# コンテナの中で、トンネルを張って psql を実行する。引数はそのまま psql に渡される
#   db_psql -v count=10 -f /data/postgres/crud/insert.sql
db_psql() {
  build_db_tools_image
  run docker compose -f "$DB_COMPOSE_FILE" run --rm -T tools "$@"
}
