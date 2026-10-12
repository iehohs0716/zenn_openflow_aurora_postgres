# Terraform Backend設定
# 既存のtfstate用S3バケットを使用（stateロックはS3ネイティブのuse_lockfile）
# バケット名は個人環境の値のため、コミットしない backend.tfbackend で渡す (backend ブロックには変数が使えない)。
# .env の TF_CLI_ARGS_init が terraform init に -backend-config=<backend.tfbackend> を足す (.env.sample と backend.tfbackend.sample を参照)。

terraform {
  backend "s3" {
  }

  required_version = ">= 1.10"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    snowflake = {
      # 登録名は snowflakedb/snowflake (旧 Snowflake-Labs/snowflake は 1.0.5 で更新が止まっている)
      source  = "snowflakedb/snowflake"
      version = "~> 2.21"
    }
  }
}

# Snowflake provider。接続先とユーザーは .env (SNOWFLAKE_ORGANIZATION_NAME / SNOWFLAKE_ACCOUNT_NAME /
# SNOWFLAKE_USER / SNOWFLAKE_AUTHENTICATOR=SNOWFLAKE_JWT / SNOWFLAKE_ROLE) から環境変数で渡す。
# 秘密鍵は、パスだけを tfvars (snowflake_private_key_path) で指定する (鍵の中身を環境変数やシェル履歴に残さない)。
# 注意: この provider は plan / destroy の時点で Snowflake に接続する。-target で AWS 側だけを対象にすれば
#       接続しないが、対象指定なしの plan / destroy (destroy.sh) には Snowflake の接続情報が必要
provider "snowflake" {
  private_key = file(pathexpand(var.snowflake_private_key_path))

  # Openflow の Deployment / Runtime / コネクタと、External Access Integration のリソースはプレビュー機能
  preview_features_enabled = [
    "snowflake_external_access_integration_resource",
    "snowflake_openflow_deployment_snowflake_managed_resource",
    "snowflake_openflow_runtime_resource",
    "snowflake_openflow_connector_resource",
  ]
}

provider "aws" {
  region = var.aws_region
  # 必要に応じてprofileを追加

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
      Owner     = var.owner
      CreatedBy = var.owner
    }
  }
}
