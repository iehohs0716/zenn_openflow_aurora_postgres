variable "project_name" {
  description = "全リソース名のプレフィックスとタグ (Project) に使うプロジェクト名 (kebab-case)。既定値なし (tfvars で指定する)"
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.project_name))
    error_message = "project_name は小文字英数字とハイフンのみ (先頭と末尾は英数字) で指定してください。"
  }
}

variable "owner" {
  description = "全リソースのタグ (Owner / CreatedBy) に付ける作成者の識別子。既定値なし (tfvars で指定する)"
  type        = string
}

variable "aws_region" {
  description = "AWS Region"
  type        = string
  default     = "ap-northeast-1"
}

variable "vpc_cidr" {
  description = "VPC の CIDR ブロック"
  type        = string
  default     = "10.0.0.0/16"
}

variable "availability_zones" {
  description = "使用するAZ。Aurora (DB Subnet Group) は2AZ以上が必要"
  type        = list(string)
  default     = ["ap-northeast-1a", "ap-northeast-1c"]
}

variable "public_subnet_cidrs" {
  description = "パブリックサブネットの CIDR (availability_zones と同数)"
  type        = list(string)
  default     = ["10.0.0.0/24", "10.0.1.0/24"]
}

variable "private_subnet_cidrs" {
  description = "プライベートサブネットの CIDR (availability_zones と同数)"
  type        = list(string)
  default     = ["10.0.10.0/24", "10.0.11.0/24"]
}

variable "enable_nat_gateway" {
  description = "プライベートサブネットからの外向き通信用に NAT Gateway (1台) を作成するか。コスト削減のため不要なら false"
  type        = bool
  default     = true
}

variable "db_port" {
  description = "DB のポート。エンジンにより 5432 (PostgreSQL) / 3306 (MySQL)"
  type        = number
  default     = 5432
}

variable "dcp_agent_count" {
  description = "DCP エージェント EC2 の台数。PoC は 1、HA は 2 (2AZ に分散)"
  type        = number
  default     = 1
}

variable "aurora_engine" {
  description = "Aurora のエンジン (aurora-postgresql / aurora-mysql)。切り替え時は db_port とパラメータグループファミリーも合わせる"
  type        = string
  default     = "aurora-postgresql"

  validation {
    condition     = contains(["aurora-postgresql", "aurora-mysql"], var.aurora_engine)
    error_message = "aurora_engine は aurora-postgresql または aurora-mysql を指定してください。"
  }
}

variable "aurora_engine_version" {
  description = "Aurora のエンジンバージョン。null なら、そのリージョンで AWS が既定とするバージョンを使う (parameter group のファミリーも自動で決まる)"
  type        = string
  default     = null
}

variable "aurora_database_name" {
  description = "Aurora の初期データベース名"
  type        = string
  default     = "appdb"
}

variable "aurora_master_username" {
  description = "Aurora のマスターユーザー名 (パスワードは Secrets Manager が管理)"
  type        = string
  default     = "postgres"
}

variable "aurora_instance_class" {
  description = "Aurora の DB インスタンスクラス"
  type        = string
  default     = "db.t4g.medium"
}

variable "snowflake_private_key_path" {
  description = "Snowflake のキーペア認証の秘密鍵 (PEM) のパス。provider と scripts/6_sync_dcp_token.sh が使う"
  type        = string
}

variable "snowflake_dcp_name" {
  description = "作成する DCP オブジェクト名"
  type        = string
}

variable "snowflake_database" {
  description = "DCP 用ネットワークルールを作成する Snowflake のデータベース名 (既存のもの)"
  type        = string
}

variable "snowflake_schema" {
  description = "DCP 用ネットワークルールを作成する Snowflake のスキーマ名 (既存のもの)"
  type        = string
}

variable "snowflake_warehouse" {
  description = "Openflow のコネクタが MERGE に使う Snowflake のウェアハウス名 (既存のもの。作成はしない)"
  type        = string
}

variable "snowflake_openflow_admin_role" {
  description = "Openflow の Runtime / コネクタを操作する Snowflake のロール名 (作成する)。公式の手順が OPENFLOW_ADMIN を使う"
  type        = string
  default     = "OPENFLOW_ADMIN"
}

variable "snowflake_openflow_runtime_role" {
  description = "Openflow の Runtime の EXECUTE_AS_ROLE に指定する Snowflake のロール名 (作成する)。仮の名称"
  type        = string
  default     = "OPENFLOW_RUNTIME_ROLE"
}

variable "snowflake_openflow_deployment" {
  description = "Runtime を作成する Openflow の Deployment 名 (Snowflake Deployment)。この名前で作成する"
  type        = string
  default     = "AURORA_CDC_DEPLOYMENT"

  validation {
    condition     = can(regex("^[A-Za-z_][A-Za-z0-9_$]*$", var.snowflake_openflow_deployment))
    error_message = "snowflake_openflow_deployment は引用符なしで書ける Snowflake 識別子 (英数字・_・$、先頭は英字か _) を指定してください。"
  }
}

variable "snowflake_openflow_runtime_name" {
  description = "作成する Openflow の Runtime 名 (snowflake_database.snowflake_schema の中に作成する)"
  type        = string
  default     = "AURORA_CDC_RUNTIME"

  validation {
    condition     = can(regex("^[A-Za-z_][A-Za-z0-9_$]*$", var.snowflake_openflow_runtime_name))
    error_message = "snowflake_openflow_runtime_name は引用符なしで書ける Snowflake 識別子 (英数字・_・$、先頭は英字か _) を指定してください。"
  }
}

variable "snowflake_openflow_connector_name" {
  description = "作成する Openflow のコネクタ名 (snowflake_database.snowflake_schema の中に作成する)。既定値なし (tfvars で指定する)"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z_][A-Za-z0-9_$]*$", var.snowflake_openflow_connector_name))
    error_message = "snowflake_openflow_connector_name は引用符なしで書ける Snowflake 識別子 (英数字・_・$、先頭は英字か _) を指定してください。"
  }
}

variable "snowflake_openflow_connector_display_name" {
  description = "Openflow のコネクタの表示名 (UI に出る別名)。未指定なら設定しない"
  type        = string
  default     = null
}

variable "snowflake_openflow_admin_granted_to_roles" {
  description = "OPENFLOW_ADMIN を付与するロール。Runtime を作成する Terraform / スクリプトの実行ロール (.env の SNOWFLAKE_ROLE) を指定する"
  type        = list(string)
}
