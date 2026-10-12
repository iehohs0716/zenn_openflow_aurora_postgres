variable "name" {
  description = "リソース名のプレフィックス"
  type        = string
}

variable "vpc_id" {
  description = "踏み台を配置する VPC ID"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC の CIDR。名前解決 (53) の許可と、db_security_group_ids 未指定時の DB 宛許可に使う"
  type        = string
}

variable "subnet_id" {
  description = "踏み台を配置するプライベートサブネット ID (SSM への到達に NAT Gateway などの外向き 443 が必要)"
  type        = string
}

variable "instance_type" {
  description = "踏み台 EC2 のインスタンスタイプ (SSM ポートフォワーディングの中継のみ)"
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
