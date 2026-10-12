# zenn_openflow_aurora_postgres

Amazon Aurora (PostgreSQL 互換) の差分 (CDC) が Snowflake Openflow を経由して Snowflake に到達し、永続化されることを確認する PoC リポジトリです。本番運用向けではなく、E2E の疎通確認が目的です。

```
Aurora (ソースDB) ── 差分CDC ──> Openflow (SPCS) ──> Snowflake (永続化)
```

- Aurora はプライベートサブネットに置き、SPCS からは Data Connectivity Proxy (DCP) 経由で接続します。
- AWS / Snowflake のリソースはすべて Terraform で管理します。
- 詳しい方針・設計は [AGENTS.md](./AGEN

## 必要なツール

| ツール | 用途 | 備考 |
| --- | --- | --- |
| Terraform (>= 1.10) | AWS / Snowflake リソースの構築 | `brew install terraform` |
| AWS CLI | AWS 認証確認、リソース操作 | `brew install awscli` |
| aws-vault | AWS 認証 (MFA) | 任意。あればスクリプトが使用有無を対話で確認 |
| Snowflake CLI (`snow`) | DCP トークン生成、シークレット更新、状態確認 | `brew install snowflake-cli` |
| Docker | `psql` / `session-manager-plugin` を動かすツールのコンテナ | Docker Desktop / Rancher Desktop など。起動しておく |
| jq | JSON 処理 | `brew install jq` |
| openssl | シークレット用パスワード生成など | macOS 標準で可 |
| bash | スクリプトの実行 | `set -euo pipefail` 前提 |

`psql` と `session-manager-plugin` は手元に入れる必要はありません (`data/docker-compose.yml` のコンテナ内で実行します)。

### アカウント・権限などの前提

- AWS アカウントと、Terraform state 用の S3 バケット (`use_lockfile` を使用)
- Snowflake アカウント (Enterprise)。Terraform / `snow` で接続できるユーザーと秘密鍵 (JWT 認証)
- リージョンは `ap-northeast-1`

## セットアップ

```bash
cp .env.sample .env
cp infra/env/dev/terraform.tfvars.sample infra/env/dev/terraform.tfvars
cp infra/env/dev/backend.tfbackend.sample infra/env/dev/backend.tfbackend
```

- `.env`: `AWS_PROFILE`、`SNOWFLAKE_*` の接続情報、`TF_CLI_ARGS_init` (`backend.tfbackend` の絶対パス) を設定
- `terraform.tfvars`: `project_name`、`snowflake_private_key_path` などを設定
- `backend.tfbackend`: state 用 S3 バケット名を設定

`.env` / `*.tfvars` / `backend.tfbackend` / 秘密鍵はコミットしません (`.gitignore` 済み)。

## スクリプト

番号順に実行します。`apply` を伴うものは plan を表示して確認を取ります。

| スクリプト | 内容 | 課金 |
| --- | --- | --- |
| `1_deploy_network.sh` | VPC / サブネット / NAT Gateway、DCP トークン用シークレット | NAT Gateway |
| `2_deploy_aurora.sh` | Aurora クラスタ、レプリケーションユーザー用シークレット | Aurora |
| `3_deploy_aurora_bastion.sh` | SQL 投入用の踏み台 EC2 | EC2 |
| `4_execute_sql_to_aurora.sh` | スキーマ・初期データ・CDC 用ユーザー/publication を投入 | - |
| `5_deploy_snowflake_dcp.sh` | Snowflake の DCP オブジェクトと接続設定 (ネットワークルール / EAI) | - |
| `6_sync_dcp_token.sh` | DCP のトークンを生成し Secrets Manager に同期 | - |
| `7_deploy_dcp_agent.sh` | DCP エージェント (EC2 + Docker) | EC2 |
| `8_create_openflow_runtime.sh` | Openflow 用ロール / シークレット / Deployment・Runtime | Runtime |
| `9_create_openflow_connector.sh` | Openflow コネクタ (オブジェクトのみ。パラメータ設定と起動は Snowsight) | - |
| `crud_sample.sh` | サンプルテーブルへ insert / update / delete / select | - |
| `check_*.sh` | DCP エージェント・DCP・Snowflake テーブル・レプリケーションスロットの状態確認 (読み取りのみ) | - |
| `restart_dcp_agent.sh` | DCP エージェントのコンテナを再起動 | - |
| `destroy.sh` | 全リソース削除 (検証後のコスト抑制のため忘れず実行) | - |

```bash
./scripts/1_deploy_network.sh
./scripts/2_deploy_aurora.sh
# ... 09 まで順に実行
./scripts/crud_sample.sh insert --count 10   # CDC の発生源
./scripts/destroy.sh                         # 後片付け
```

## フォルダ構造

```
.
├── AGENTS.md              エージェント向けのガイド (方針・設計の詳細)
├── README.md
├── .env.sample            環境変数のサンプル (.env はコミットしない)
├── infra/
│   ├── env/dev/           ルートモジュール (main.tf, variables.tf, backend.tf, terraform.tfvars.sample ほか)
│   └── modules/
│       ├── aws_vpc/                    VPC / サブネット / NAT GW
│       ├── aws_aurora/                 Aurora クラスタ / インスタンス / parameter group
│       ├── aws_bastion/                SQL 投入用の踏み台 EC2 (SSM のみ)
│       ├── aws_dcp_agent/              DCP エージェント用 EC2 (Docker)
│       ├── aws_secretsmanager_secret/  値を Terraform 管理外にするシークレット
│       ├── snowflake_dcp/              DCP オブジェクトと接続設定
│       ├── snowflake_openflow_roles/   Openflow 用ロールと権限
│       ├── snowflake_openflow_runtime/ Openflow の Deployment / Runtime
│       ├── snowflake_openflow_connector/ Openflow のコネクタ
│       └── snowflake_secret/           値を Terraform 管理外にする Snowflake のシークレット
├── data/
│   ├── docker-compose.yml  psql / AWS CLI / session-manager-plugin / jq を含むツールのコンテナ
│   ├── docker/             Dockerfile とコンテナ内で動く run.sh
│   └── postgres/           schema / seed / cdc / crud / check の SQL (エンジン別。MySQL は data/mysql/ を追加)
├── scripts/                番号順のデプロイ・操作スクリプト
│   └── common/             スクリプト共通の関数
├── docs/
│   └── arch/               アーキテクチャ図 (drawio)
└── knowledge/              検証結果・ハマりどころのメモ
```
