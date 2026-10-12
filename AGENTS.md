# AGENTS.md

このファイルは、本リポジトリで作業する各エージェント向けのガイドです。

## リポジトリの目的

Amazon Aurora を構築してデータを流し込み、その差分 (CDC) が Snowflake Openflow を経由して Snowflake に到達し、何らかの形で永続化されることを検証する PoC リポジトリ。

```
Aurora (ソースDB) ── 差分CDC ──> Openflow ──> Snowflake (永続化)
```

本番運用向けではなく、**E2E の疎通確認が目的**。

## 検証したいこと

- Aurora への初期データ投入と、その後の INSERT / UPDATE / DELETE が CDC として取得されること
- Openflow (CDC コネクタ) が差分を Snowflake へ連携できること
- Snowflake 側でデータが永続化されること (テーブル形式・履歴の持ち方などは検証しながら確認)
- 差分の欠落・重複・順序、遅延がどの程度かの観測

## 方針

- IaC は **Terraform** (>= 1.10)。AWS リソースは必ず Terraform で管理し、手動で作らない。
- Aurora のエンジンは当面 **PostgreSQL 互換**。ただし**将来 MySQL 互換等へ切り替えられる構成**にする (下記「エンジン切り替え」参照)。
- Openflow は **SPCS (Snowflake Deployment) 一択**。BYOC は採用しない。
- Aurora インスタンスは **プライベートサブネット**に配置する (公開しない)。SPCS から Aurora へは **Data Connectivity Proxy (DCP)** で接続する。
  - 前提: アカウントは Enterprise。アウトバウンド PrivateLink は Business Critical 以上が必要なため使えない。要件は「プライベートの Aurora と Snowflake がつながること」で、方式は問わない。
  - 構成: プライベートサブネットの EC2 (Docker, `snowflakedb/dcp-client`) が 443 で Snowflake へアウトバウンド接続しトンネルを張る → Aurora **ライター**エンドポイント (FQDN:5432) へ接続。NLB / Endpoint Service は不要。NAT Gateway 経由の外向き 443 が必要 (`enable_nat_gateway = true`)。
  - Snowflake 側は `CREATE DATA CONNECTIVITY PROXY`、`DATA_CONNECTIVITY_PROXY_EGRESS` のネットワークルール、EAI。証明書発行は非同期 (30分以上待つ)。ネットワークルール/EAI に `CREATE OR REPLACE` は使わない。
  - **未検証リスク**: PostgreSQL の論理レプリケーションが DCP のトンネル越しで安定動作するか (実績未確認)。代替は Business Critical + PrivateLink。
  - エージェントは EC2 (Docker) で動かす。ECS Fargate はトークンをファイルで渡す必要があり、PoC では採用しない。Terraform は `infra/modules/aws_dcp_agent` に置く。トークンの置き場 (Secrets Manager のシークレット) は `infra/modules/aws_secretsmanager_secret` で作り (プレースホルダで作成、`ignore_changes`)、実値は `scripts/6_sync_dcp_token.sh` が Snowflake で生成して投入する (環境変数や手動の貼り付けは使わない。user_data や tfstate に秘密を残さない)。DCP オブジェクト自体も `infra/modules/snowflake_dcp` で Terraform 管理する。
  - 詳細は `knowledge/20261002_snowflake-data-connectivity-proxy-dcp.md` と `knowledge/20261002_dcp-agent-ec2-terraform-design.md`。
- データ生成は **bash + psql**。private サブネットの Aurora へは、SSM ポートフォワーディング (DCP エージェントとは独立した踏み台 EC2、`infra/modules/aws_bastion` を中継にする) で届く。`psql` と `session-manager-plugin` は、手元に入れず、ツールのコンテナ (`data/docker-compose.yml`) の中で実行する (作業者の環境を汚さない。手元に必要なのは Docker だけ)。スキーマ管理は **Rust 製ツール**を試す (`sqlx-cli` が有力。PostgreSQL / MySQL 両対応のため)。
- Snowflake の接続情報 (`SNOWFLAKE_ORGANIZATION_NAME` / `SNOWFLAKE_ACCOUNT_NAME` / `SNOWFLAKE_USER` / `SNOWFLAKE_AUTHENTICATOR` / `SNOWFLAKE_ROLE`) は `.env` に書く (`.env.sample` を参照)。秘密鍵はパスだけを `terraform.tfvars` の `snowflake_private_key_path` で指定する。snowflake provider は plan / destroy の時点で Snowflake に接続するため、対象指定なしの `destroy.sh` には接続情報が必要 (`-target` 付きの `deploy_*.sh` は不要)。
- 認証情報や `*.tfvars` はコミットしない (`.gitignore` 済み)。`.env` は読まない・出力しない。

## ディレクトリ構成

```
infra/
  env/dev/          環境ごとのルートモジュール (main.tf, variables.tf, outputs.tf, backend.tf, terraform.tfvars[.sample])
  modules/
    aws_vpc/        VPC / パブリック・プライベートサブネット (2AZ) / IGW / NAT GW(任意)
    aws_aurora/     Aurora クラスタ / インスタンス / SG / Subnet Group / クラスタ parameter group (CDC 設定は変数で受ける) / マスターパスワードは Secrets Manager 管理
    aws_bastion/    Aurora への SQL 投入用の踏み台 EC2 / SG / IAM (SSM Session Manager のみ、インバウンドなし。DCP エージェントとは独立)
    aws_dcp_agent/  DCP エージェント用 EC2 (Docker) / SG / IAM (トークンの読み取り権限)
    aws_secretsmanager_secret/  値を Terraform 管理外にする Secrets Manager のシークレット (プレースホルダで作成。DCP のトークン置き場に使う)
    snowflake_dcp/  Snowflake の DCP オブジェクトと、DCP 用の接続設定 (ネットワークルール / EAI / DCP への関連付け)。DCP 本体・ネットワークルール・関連付けは snowflake_execute (provider が DCP 用のモードに未対応のため)、EAI はネイティブのリソース。Aurora のライターエンドポイントを受けるため、Aurora の後に作る
    snowflake_openflow_runtime/  Openflow の Deployment / Runtime (provider のプレビュー機能のリソース。DCP 用 EAI の付与と、実行ロールへの USAGE も含む)
    snowflake_openflow_connector/  Openflow のコネクタ (provider のプレビュー機能のリソース。カタログ定義 OPENFLOW_POSTGRES_CDC から作成。名前は変数で外から与える。パラメータ設定と起動は管理外で UI)
    snowflake_openflow_roles/  Openflow 用のロール (OPENFLOW_ADMIN / Runtime の実行ロール) と、既存の DB・スキーマ・ウェアハウスへの権限 (ネイティブのリソース。CREATE OPENFLOW RUNTIME / CONNECTOR の権限だけ provider での対応を確認できず snowflake_execute。DB・スキーマ・ウェアハウスは作らず、変数で受ける)
    snowflake_secret/  値を Terraform 管理外にする Snowflake のシークレット (GENERIC_STRING。プレースホルダで作成、`ignore_changes`。Runtime の実行ロールへの READ 付与つき。実値は ALTER SECRET で投入する。Openflow のコネクタが Aurora に接続するパスワード用)
data/
  docker-compose.yml  Aurora へ SQL を送るツールのコンテナ (psql / AWS CLI / session-manager-plugin / jq)。docker/ に Dockerfile とコンテナ内で動く run.sh (トンネルを張る → psql を実行 → 閉じる)
  postgres/         PostgreSQL 用のサンプル。schema/ (スキーマ・テーブル) / seed/ (初期データ) / cdc/ (Openflow 用のレプリケーションユーザーと publication) / crud/ (insert・update・delete・select) / check/ (確認用の読み取り SQL)。エンジンを切り替えるときは data/mysql/ を追加する
scripts/
  1_deploy_network.sh  VPC / サブネット / NAT Gateway と、DCP トークン用のシークレット (空の入れ物) を plan → 確認 → apply (-target)
  2_deploy_aurora.sh   Aurora と、Openflow 用レプリケーションユーザーのパスワードのシークレットだけを plan → 確認 → apply (-target=module.aurora, module.aurora_repl_secret。課金あり)
  3_deploy_aurora_bastion.sh  踏み台 (EC2) だけを plan → 確認 → apply (-target=module.bastion。Aurora 作成済みの事前チェックあり。課金あり)
  4_execute_sql_to_aurora.sh  data/<エンジン>/schema・seed・cdc の SQL を Aurora に投入 (繰り返し実行できる。ツールのコンテナ経由)。cdc は Openflow 用のレプリケーションユーザーと publication。パスワードは未投入なら生成してシークレットに投入
  5_deploy_snowflake_dcp.sh  Snowflake 側の DCP オブジェクト / DCP 用の接続設定 (ネットワークルール・EAI・DCP への関連付け) を 1 回の plan → 確認 → apply (-target=module.snowflake_dcp。Aurora 作成済みの事前チェックあり)
  6_sync_dcp_token.sh  Snowflake でブートストラップトークンを生成 (snow sql) し、Secrets Manager のシークレットに投入 (有効なら何もしない。--force / --days)
  7_deploy_dcp_agent.sh  DCP エージェントだけを plan → 確認 → apply (-target=module.dcp_agent。トークン同期済みか事前チェック)
  8_create_openflow_runtime.sh  Openflow 用のロール / Snowflake のシークレット (空の入れ物) / Deployment と Runtime だけを plan → 確認 → apply (-target=module.snowflake_openflow_roles, module.snowflake_aurora_repl_secret, module.snowflake_openflow_runtime。provider ではプレビュー機能。DCP 用 EAI を付与)。続けて、ソース DB (openflow_repl) のパスワードをシークレットに設定 (値の更新 ALTER SECRET だけ snow sql)。シークレットの作成と実行ロールへの READ は Terraform。コネクタの導入・設定は Snowsight で手作業
  9_create_openflow_connector.sh  Openflow のコネクタ (オブジェクトのみ) だけを plan → 確認 → apply (-target=module.snowflake_openflow_connector。Runtime 作成済みの事前チェックあり)。パラメータ設定と起動は UI
  crud_sample.sh    サンプルのテーブルに insert / update / delete / select を実行 (--count / --batch。ツールのコンテナ経由)
  common/           スクリプト共通の関数 (source して使う)。setup.sh (初期化・check_command・.env 読込・確認プロンプト) / aws.sh (aws-vault の選択・run ラッパー・AWS 認証確認) / terraform.sh (init・tf_eval) / snowflake.sh (Snowflake の接続情報と tfvars の事前チェック) / db.sh (ツールのコンテナ経由で Aurora に SQL を送る) / env.sh (.env を読み込むだけ。手動で source する用)
  restart_dcp_agent.sh DCP エージェントのコンテナを SSM 経由で再起動 (terraform output からインスタンス特定。トークンを Secrets Manager から取り直して再起動)
  check_dcp_agent.sh   DCP エージェント EC2 の状態確認 (SSM 経由で docker ps / logs / cloud-init を取得。読み取りのみ)
  check_dcp_snowflake.sh  Snowflake 側の DCP の状態確認 (snow sql で DESCRIBE DATA CONNECTIVITY PROXY を実行。読み取りのみ)
  check_snowflake_tables.sh  Snowflake の宛先テーブル 2 つ (customers / orders) に SELECT * を実行して表示 (SQL 全文も出力。読み取りのみ)
  check_aurora_replication.sh  Aurora のレプリケーションスロットの状態を確認 (data/<エンジン>/check/ の SQL を実行。ツールのコンテナ経由。読み取りのみ)
  destroy.sh        .env 読込 → init → destroy (対象指定なしのため Snowflake の接続情報が必要)
docs/               ドキュメント
.env(.sample)       AWS_PROFILE (既定: ds-sandbox)
```

現状は、VPC / DCP トークンのシークレット / Snowflake の DCP オブジェクト / DCP エージェント / Aurora / Snowflake 側の DCP 用設定が実装済み (`terraform validate` 済み)。Openflow のランタイム・コネクタ関連は未実装。

## 開発コマンド

```bash
./scripts/1_deploy_network.sh   # VPC とトークン用のシークレットを構築 (NAT Gateway の課金あり。aws-vault 使用有無を対話で選択)
./scripts/2_deploy_aurora.sh    # Aurora 構築 (課金あり)
./scripts/3_deploy_aurora_bastion.sh   # 踏み台 (SQL 投入の中継用 EC2) を構築 (課金あり)
./scripts/4_execute_sql_to_aurora.sh   # サンプルのスキーマ・初期データを Aurora に投入 (Docker が必要)
./scripts/5_deploy_snowflake_dcp.sh  # Snowflake 側の DCP オブジェクト / DCP 用の接続設定を作成 (Aurora の後。.env の SNOWFLAKE_* と terraform.tfvars の設定が必要)
./scripts/6_sync_dcp_token.sh   # トークンを生成してシークレットに同期 (期限切れが近いときも再実行する)
./scripts/7_deploy_dcp_agent.sh # DCP エージェント構築 (トークン同期済みであること)
./scripts/8_create_openflow_runtime.sh  # Openflow 用のロール / シークレット / Deployment と Runtime を構築 (Runtime の課金あり)
./scripts/9_create_openflow_connector.sh  # Openflow のコネクタ (オブジェクトのみ) を作成。パラメータの設定と起動は UI
./scripts/crud_sample.sh insert --count 10  # CRUD の実行 (insert / update / delete / select)
./scripts/destroy.sh   # 全リソース削除 (検証後のコスト抑制のため忘れず実行)
cd infra/env/dev && terraform fmt -recursive ../.. && terraform validate
```

- backend: S3 (バケット名は `infra/env/dev/backend.tfbackend` の `bucket`。コミットしない。`.env` の `TF_CLI_ARGS_init` で `terraform init` に渡す。`.env.sample` と `backend.tfbackend.sample` を参照。key `openflow_aurora/terraform.tfstate`, `use_lockfile`)。
- provider: `hashicorp/aws ~> 5.0`、リージョン `ap-northeast-1`。
- 命名プレフィックスは `locals.project_name_kebab` (= `terraform.tfvars` の `project_name`。コミットしない)。`default_tags` で全リソースにタグ付与。
- `apply` / `destroy` は課金・破壊を伴うため、ユーザーの明示的な指示なしに実行しない。`plan` までは可。

## Aurora モジュール設計 (エンジン切り替え)

`infra/modules/aws_aurora/` は、以下を守る。

- エンジン固有の値をモジュール内にハードコードしない。`engine` (`aurora-postgresql` / `aurora-mysql`)、`engine_version`、`port`、`parameter_group_family` を変数化する。
- CDC に必要な設定はエンジンごとに異なるため、cluster parameter group のパラメータを変数 (map/list) で外から渡す。
  - PostgreSQL: `rds.logical_replication = 1` (論理レプリケーション。レプリケーションスロット/パブリケーションが必要)
  - MySQL: binlog 有効化 (`binlog_format = ROW` 等)
  - 上記は一例。実際の設定は公式ドキュメントで確認してから書く。
- エンジンごとの既定値は `env/dev` 側 (tfvars / locals) に寄せ、`engine` を変えるだけで切り替わる形を目指す。
- DB 内スキーマ・サンプルデータ・CRUD の SQL は、エンジン別にディレクトリを分けて `data/` に置く (例: `data/postgres/`, `data/mysql/`)。CDC 用ユーザー/パブリケーション作成 SQL も同様。
- Security Group はプライベートサブネット内から `port` 変数で許可する (5432 固定にしない)。
- Openflow 側のコネクタもエンジンで異なる (PostgreSQL / MySQL 用)。エンジンごとの設定は `docs/` に記載する。

## 作業ルール

- 課金が発生するリソース (Aurora クラスタ、NAT Gateway、Openflow Deployment 等) を追加するときは、コスト影響を一言添える。
- 外部サービス (Openflow / Snowflake / Aurora) の仕様は変更が早いため、設定値は公式ドキュメントで確認してから書く。推測で書かない。
- 検証結果 (確認できたこと・ハマった点) は `knowledge/` 配下に Markdown で残す。
- 既存の `scripts/*.sh` のスタイル (日本語メッセージ、`set -euo pipefail`、`.env` 読込) に合わせる。

## 言語・スタイル

- ドキュメント、コメント、`description`、コミットメッセージ、会話は日本語。
- コード中の識別子・技術用語は英語のまま。

## 未決事項

- 合格基準 (宛先テーブルの最新状態一致のみか、ジャーナルテーブルで欠落・重複・順序まで見るか)
- Snowflake アカウントのエディションの最終確認 (Enterprise と聞いている。Snowsight で確認)
- DCP エージェントの台数 (PoC は1台、HA は2AZ2台)
- Snowflake 側オブジェクト (DB / ウェアハウス / ネットワークルール / EAI) を Terraform (snowflake provider) で管理するか、SQL スクリプトにするか
- スキーマ管理ツールの最終選定 (`sqlx-cli` / `refinery`)

