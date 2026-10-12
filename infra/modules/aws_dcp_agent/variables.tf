variable "name" {
  description = "リソース名のプレフィックス"
  type        = string
}

variable "vpc_id" {
  description = "エージェントを配置する VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC の CIDR。名前解決 (53) の許可と、db_security_group_ids 未指定時の DB 宛許可に使う"
  type        = string
}

variable "subnet_ids" {
  description = "エージェントを配置するプライベートサブネット ID (HA 時は複数 AZ)"
  type        = list(string)
}

variable "instance_count" {
  description = "エージェント EC2 の台数。PoC は 1、HA は 2 (subnet_ids に順番に分散配置)"
  type        = number
  default     = 1

  validation {
    condition     = var.instance_count >= 1
    error_message = "instance_count は 1 以上を指定してください。"
  }
}

variable "instance_type" {
  description = "エージェント EC2 のインスタンスタイプ (x86_64。arm64 のイメージ対応は未確認)"
  type        = string
  default     = "t3.micro"
}

variable "db_port" {
  description = "アウトバウンドで許可する DB ポート (エンジンにより 5432 / 3306 等)"
  type        = number
}

variable "db_security_group_ids" {
  description = "DB 側 SG ID のリスト。指定時は DB ポートの送信先をこの SG に限定する。空の場合は VPC CIDR 宛に許可する"
  type        = list(string)
  default     = []
}

variable "bootstrap_token_secret_arn" {
  description = "DCP ブートストラップトークンを格納する Secrets Manager のシークレットの ARN (EC2 に読み取り権限を付与する)。シークレットは modules/aws_secretsmanager_secret で作り、値は scripts/6_sync_dcp_token.sh が投入する"
  type        = string
}

variable "bootstrap_token_secret_name" {
  description = "DCP ブートストラップトークンを格納する Secrets Manager のシークレット名 (user_data が起動時に値を取得する)"
  type        = string
}

variable "agent_image" {
  description = "DCP エージェントの Docker イメージ"
  type        = string
  default     = "snowflakedb/dcp-client:latest"
}

variable "metrics_cidr_blocks" {
  description = "Prometheus メトリクス (9092) を許可する CIDR。空なら開放しない"
  type        = list(string)
  default     = []
}
