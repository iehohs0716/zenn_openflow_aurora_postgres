locals {
  env                = "dev"
  project_name_kebab = var.project_name

  # DCP ブートストラップトークンの Secrets Manager シークレット名 (scripts/6_sync_dcp_token.sh も terraform console で参照する)
  dcp_token_secret_name = "${local.project_name_kebab}/dcp/bootstrap-token"

  # Openflow のコネクタ用レプリケーションユーザー (openflow_repl) のパスワードを置く Secrets Manager のシークレット名
  # (scripts/4_execute_sql_to_aurora.sh も terraform console で参照する)
  aurora_repl_secret_name = "${local.project_name_kebab}/aurora/openflow-repl-password"

  # 同じパスワードを置く Snowflake 側のシークレット名 (コネクタの設定から参照される。scripts/8_create_openflow_runtime.sh も terraform console で参照する)
  snowflake_aurora_repl_secret_name = "AURORA_REPL_PASSWORD"

  # Aurora の変更を Openflow に送る (CDC) ために必要なクラスタパラメータ。エンジンごとに異なるため engine をキーにする
  # PostgreSQL は論理レプリケーションを有効にしないと、Openflow のコネクタが変更を読み取れない (静的パラメータ。反映には再起動が必要)
  # (aurora-mysql の値は一例。切り替え時に公式ドキュメントで確認する)
  aurora_cdc_parameters = {
    "aurora-postgresql" = [
      { name = "rds.logical_replication", value = "1", apply_method = "pending-reboot" },
    ]
    "aurora-mysql" = [
      { name = "binlog_format", value = "ROW", apply_method = "pending-reboot" },
    ]
  }
}

# =============================================
# 構築の順序 (scripts/ の番号と対応する)
#   1. VPC / サブネット / NAT Gateway と、トークン用のシークレット (空の入れ物)
#   2. Aurora と、Openflow 用レプリケーションユーザーのパスワードのシークレット (空の入れ物)
#   3. 踏み台 (EC2。DCP エージェントとは独立。Aurora への SQL 投入時の SSM ポートフォワーディングの中継)
#   4. (Terraform 管理外) Aurora への SQL 投入。Openflow 用のユーザー・publication の作成と、パスワードの投入 (scripts/4_execute_sql_to_aurora.sh)
#   5. Snowflake の DCP オブジェクトと、DCP 用ネットワークルール / EAI / DCP への関連付け
#   6. トークンを生成してシークレットに同期 (Terraform 管理外。scripts/6_sync_dcp_token.sh)
#   7. DCP エージェント (EC2)
#   8. Openflow 用のロール (既存の DB・スキーマ・ウェアハウスに対する権限)、コネクタが Aurora に接続するパスワードの Snowflake のシークレット (空の入れ物)、
#      Openflow の Deployment と Runtime (シークレットの値は scripts/8_create_openflow_runtime.sh が投入する)
#   9. Openflow のコネクタ (オブジェクトのみ。パラメータの設定と起動は Openflow の UI)
# =============================================

# =============================================
# 1. VPC / サブネット (パブリック・プライベート)
# =============================================

module "vpc" {
  source = "../../modules/aws_vpc"

  name                 = local.project_name_kebab
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
  enable_nat_gateway   = var.enable_nat_gateway
}

# =============================================
# 1. DCP ブートストラップトークンのシークレット
# 値は Terraform 管理外 (プレースホルダで作成し、scripts/6_sync_dcp_token.sh が実値を投入する)
# =============================================

module "dcp_token_secret" {
  source = "../../modules/aws_secretsmanager_secret"

  name        = local.dcp_token_secret_name
  description = "DCP エージェントのブートストラップトークン (値は Terraform 管理外。scripts/6_sync_dcp_token.sh が投入する)"
}

# =============================================
# 5. Snowflake の DCP オブジェクト
# snowflake provider が DCP に未対応のため snowflake_execute で実行する。
# 前提: .env に Snowflake の接続情報、terraform.tfvars に snowflake_private_key_path を設定していること。
# =============================================

module "snowflake_dcp" {
  source = "../../modules/snowflake_dcp"

  name        = var.snowflake_dcp_name
  database    = var.snowflake_database
  schema      = var.snowflake_schema
  target_host = module.aurora.writer_endpoint
  target_port = var.db_port
}

# =============================================
# 8. Openflow 用の Snowflake のロールと権限
# Runtime / コネクタの作成先と宛先は、既存のデータベース・スキーマ (snowflake_database / snowflake_schema) の中で完結させる。
# ウェアハウスも既存のものを使う (作成しない)。
# =============================================

module "snowflake_openflow_roles" {
  source = "../../modules/snowflake_openflow_roles"

  database          = var.snowflake_database
  schema            = var.snowflake_schema
  warehouse         = var.snowflake_warehouse
  admin_role_name   = var.snowflake_openflow_admin_role
  runtime_role_name = var.snowflake_openflow_runtime_role

  admin_granted_to_roles = var.snowflake_openflow_admin_granted_to_roles
}

# =============================================
# 7. DCP エージェント (Snowflake Data Connectivity Proxy)
# プライベートサブネットの Aurora と Openflow (SPCS) をつなぐ
# NAT Gateway 経由で Snowflake へ 443 アウトバウンドするため enable_nat_gateway = true が前提
# =============================================

module "dcp_agent" {
  source = "../../modules/aws_dcp_agent"

  name                        = local.project_name_kebab
  vpc_id                      = module.vpc.vpc_id
  vpc_cidr                    = module.vpc.vpc_cidr
  subnet_ids                  = module.vpc.private_subnet_ids
  instance_count              = var.dcp_agent_count
  db_port                     = var.db_port
  db_security_group_ids       = [module.aurora.security_group_id]
  bootstrap_token_secret_arn  = module.dcp_token_secret.arn
  bootstrap_token_secret_name = module.dcp_token_secret.name
}

# =============================================
# 2. Aurora (プライベートサブネット)
# Openflow (SPCS) に変更 (CDC) を送る元のデータベース。
# DCP エージェントの SG (Openflow のコネクタが DCP のトンネル経由でライターに接続する) と、
# 踏み台の SG (SQL 投入用) からのみ接続を許可する
# =============================================

# リージョンで利用可能なバージョンを AWS に問い合わせる。
# バージョン未指定なら既定バージョンを返し、parameter group のファミリーも同時に得られる
data "aws_rds_engine_version" "aurora" {
  engine  = var.aurora_engine
  version = var.aurora_engine_version
}

module "aurora" {
  source = "../../modules/aws_aurora"

  name                       = local.project_name_kebab
  vpc_id                     = module.vpc.vpc_id
  subnet_ids                 = module.vpc.private_subnet_ids
  allowed_security_group_ids = [module.dcp_agent.security_group_id, module.bastion.security_group_id]

  engine                 = var.aurora_engine
  engine_version         = data.aws_rds_engine_version.aurora.version
  parameter_group_family = data.aws_rds_engine_version.aurora.parameter_group_family
  port                   = var.db_port
  database_name          = var.aurora_database_name
  master_username        = var.aurora_master_username
  instance_class         = var.aurora_instance_class
  # Openflow に変更を送るために必要な CDC 設定 (PostgreSQL は論理レプリケーション)
  cluster_parameters = local.aurora_cdc_parameters[var.aurora_engine]
}

# =============================================
# 2. Openflow 用レプリケーションユーザーのパスワードのシークレット
# Openflow のコネクタが Aurora から変更を読み取るときの接続に使うユーザー (openflow_repl) のパスワード。
# 値は Terraform 管理外 (プレースホルダで作成し、scripts/4_execute_sql_to_aurora.sh が生成して投入する。state に残さない)
# =============================================

module "aurora_repl_secret" {
  source = "../../modules/aws_secretsmanager_secret"

  name        = local.aurora_repl_secret_name
  description = "Openflow のコネクタが Aurora の変更を読み取るユーザー (openflow_repl) のパスワード (値は Terraform 管理外。scripts/4_execute_sql_to_aurora.sh が投入する)"
}

# =============================================
# 3. 踏み台 (Aurora への SQL 投入用)
# DCP エージェントとは独立した EC2。SSM Session Manager のポートフォワーディングでだけ接続する (インバウンドなし)。
# t3.micro 1 台分の課金が発生する。不要になったら scripts/destroy.sh で削除する
# =============================================

module "bastion" {
  source = "../../modules/aws_bastion"

  name                  = local.project_name_kebab
  vpc_id                = module.vpc.vpc_id
  vpc_cidr              = module.vpc.vpc_cidr
  subnet_id             = module.vpc.private_subnet_ids[0]
  db_port               = var.db_port
  db_security_group_ids = [module.aurora.security_group_id]
}

# =============================================
# 8. Openflow のコネクタが Aurora に接続するときのパスワードを置く Snowflake のシークレット
# 作成と、Runtime の実行ロールへの READ の付与は Terraform が行う (destroy で一緒に削除される)。
# 値は Terraform 管理外 (プレースホルダで作成し、scripts/8_create_openflow_runtime.sh が ALTER SECRET で実値を投入する。state に残さない)
# =============================================

module "snowflake_aurora_repl_secret" {
  source = "../../modules/snowflake_secret"

  database   = var.snowflake_database
  schema     = var.snowflake_schema
  name       = local.snowflake_aurora_repl_secret_name
  comment    = "Openflow のコネクタが Aurora の変更を読み取るユーザー (openflow_repl) のパスワード (値は Terraform 管理外)"
  read_roles = [module.snowflake_openflow_roles.runtime_role_name]
}

# =============================================
# 8. Openflow の Deployment と Runtime
# Aurora の変更を Snowflake に取り込むコネクタの実行環境。Runtime は既存のデータベース・スキーマの中に作る。
# DCP 用 EAI (Aurora へ到達する経路) を付与するため、EAI の作成後 (scripts/6) に作る。
# Runtime が動いている間は課金が発生する (Deployment 自体は無料)。
# =============================================

module "snowflake_openflow_runtime" {
  source = "../../modules/snowflake_openflow_runtime"

  deployment_name              = var.snowflake_openflow_deployment
  database                     = var.snowflake_database
  schema                       = var.snowflake_schema
  runtime_name                 = var.snowflake_openflow_runtime_name
  execute_as_role              = module.snowflake_openflow_roles.runtime_role_name
  external_access_integrations = [module.snowflake_dcp.eai_name]
}

# =============================================
# 9. Openflow のコネクタ
# Runtime の上で動く PostgreSQL の CDC コネクタ (カタログ定義 OPENFLOW_POSTGRES_CDC から作成する)。
# 作るのはコネクタのオブジェクトだけ (STOPPED / Draft)。パラメータ (config.json) の設定と起動は Terraform 管理外 (Openflow の UI)。
# コネクタ名は変数 (snowflake_openflow_connector_name) で外から与える。
# =============================================

module "snowflake_openflow_connector" {
  source = "../../modules/snowflake_openflow_connector"

  database       = var.snowflake_database
  schema         = var.snowflake_schema
  connector_name = var.snowflake_openflow_connector_name
  runtime_name   = module.snowflake_openflow_runtime.runtime_name
  display_name   = var.snowflake_openflow_connector_display_name
}
