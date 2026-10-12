#!/bin/bash

# DCP エージェント EC2 の状態を SSM 経由で確認するスクリプト (読み取りのみ)
#
#   1. SSM の接続状態 (PingStatus)
#   2. docker ps / docker logs / cloud-init ログ
#
# 使い方:
#   ./scripts/check_dcp_agent.sh                 # terraform output の全インスタンスを確認
#   ./scripts/check_dcp_agent.sh i-0123456789    # インスタンス ID を指定
#
# Snowflake 側の確認 (こちらが正): ./scripts/check_dcp_snowflake.sh

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common/setup.sh"
source "$COMMON_DIR/terraform.sh"

check_command "terraform" "Terraformをインストールしてください: brew install terraform"
check_command "aws" "AWS CLIをインストールしてください: brew install awscli"

load_env
cd_terraform_dir

select_aws_auth

# 対象インスタンスの決定 (引数 > terraform output)
if [ $# -gt 0 ]; then
    INSTANCE_IDS=("$@")
else
    echo "🔧 terraform output からインスタンス ID を取得中..."
    run terraform init > /dev/null
    IDS="$(run terraform output -json dcp_agent_instance_ids | tr -d '[]" \n' | tr ',' ' ')"
    # shellcheck disable=SC2206
    INSTANCE_IDS=($IDS)
fi

if [ ${#INSTANCE_IDS[@]} -eq 0 ]; then
    echo "❌ 対象のインスタンスがありません (未 apply の可能性があります)"
    exit 1
fi

# EC2 上で実行する確認コマンド (SSM は root で実行されるため sudo 不要)
COMMANDS='["docker ps --filter name=dcp-agent","echo \"--- docker logs ---\"","docker logs --tail 30 dcp-agent 2>&1","echo \"--- cloud-init ---\"","tail -20 /var/log/cloud-init-output.log"]'

FAILED=0
for ID in "${INSTANCE_IDS[@]}"; do
    echo "========================================="
    echo "📋 $ID"
    echo "========================================="

    # 1. SSM の接続状態
    PING="$(run aws ssm describe-instance-information --region "$AWS_REGION_NAME" \
        --filters "Key=InstanceIds,Values=$ID" \
        --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null || true)"
    if [ "$PING" != "Online" ]; then
        echo "❌ SSM に接続できません (PingStatus: ${PING:-不明})"
        echo "   EC2 の起動直後は数分かかります。続く場合は IAM ロールと NAT Gateway 経由の 443 を確認してください"
        FAILED=1
        echo ""
        continue
    fi
    echo "✅ SSM: Online"
    echo ""

    # 2. コマンド送信
    CID="$(run aws ssm send-command --region "$AWS_REGION_NAME" \
        --instance-ids "$ID" \
        --document-name AWS-RunShellScript \
        --parameters "commands=$COMMANDS" \
        --query Command.CommandId --output text)"

    # 完了待ち (最大 60 秒)
    STATUS="Pending"
    for _ in $(seq 1 30); do
        sleep 2
        STATUS="$(run aws ssm get-command-invocation --region "$AWS_REGION_NAME" \
            --command-id "$CID" --instance-id "$ID" \
            --query Status --output text 2>/dev/null || echo "Pending")"
        case "$STATUS" in
            Pending|InProgress|Delayed) ;;
            *) break ;;
        esac
    done

    run aws ssm get-command-invocation --region "$AWS_REGION_NAME" \
        --command-id "$CID" --instance-id "$ID" \
        --query StandardOutputContent --output text
    if [ "$STATUS" != "Success" ]; then
        echo "❌ コマンドの状態: $STATUS"
        run aws ssm get-command-invocation --region "$AWS_REGION_NAME" \
            --command-id "$CID" --instance-id "$ID" \
            --query StandardErrorContent --output text
        FAILED=1
    fi
    echo ""
done

echo "========================================="
if [ "$FAILED" -eq 0 ]; then
    echo "✅ 確認完了。Snowflake 側でも状態を確認してください"
else
    echo "⚠️  確認できなかったインスタンスがあります"
fi
echo "  ./scripts/check_dcp_snowflake.sh"
echo "========================================="
