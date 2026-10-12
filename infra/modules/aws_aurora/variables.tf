variable "name" {
  description = "リソース名のプレフィックス"
  type        = string
}

variable "vpc_id" {
  description = "Aurora を配置する VPC ID"
  type        = string
}

variable "subnet_ids" {
  description = "DB Subnet Group に入れるプライベートサブネット ID (2AZ 以上)"
  type        = list(string)
}

variable "allowed_security_group_ids" {
  description = "Aurora への接続を許可する SG ID のリスト (DCP エージェントの SG、踏み台の SG など)"
  type        = list(string)
  default     = []
}

variable "engine" {
  description = "Aurora のエンジン (aurora-postgresql / aurora-mysql)"
  type        = string
  default     = "aurora-postgresql"
}

variable "engine_version" {
  description = "エンジンバージョン。parameter_group_family と整合させる"
  type        = string
}

variable "parameter_group_family" {
  description = "クラスタ parameter group のファミリー (例: aurora-postgresql16)"
  type        = string
}

variable "port" {
  description = "DB ポート (PostgreSQL は 5432、MySQL は 3306)"
  type        = number
}

variable "database_name" {
  description = "初期データベース名"
  type        = string
}

variable "master_username" {
  description = "マスターユーザー名。パスワードは Secrets Manager が管理する"
  type        = string
}

variable "instance_class" {
  description = "DB インスタンスクラス"
  type        = string
}

variable "instance_count" {
  description = "DB インスタンス数。1 台目がライター。PoC は 1"
  type        = number
  default     = 1

  validation {
    condition     = var.instance_count >= 1
    error_message = "instance_count は 1 以上を指定してください。"
  }
}

variable "cluster_parameters" {
  description = "クラスタ parameter group に設定するパラメータ。Openflow に変更を送る (CDC) ために必要な設定 (論理レプリケーションや binlog) はエンジンごとに異なるため、呼び出し側から渡す"
  type = list(object({
    name         = string
    value        = string
    apply_method = optional(string, "pending-reboot")
  }))
  default = []
}

variable "skip_final_snapshot" {
  description = "削除時に最終スナップショットを取らない。PoC は true"
  type        = bool
  default     = true
}

variable "deletion_protection" {
  description = "削除保護。PoC は false"
  type        = bool
  default     = false
}
