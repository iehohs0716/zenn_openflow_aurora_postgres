variable "database" {
  description = "コネクタを作成するデータベース名 (既存のもの)"
  type        = string
}

variable "schema" {
  description = "コネクタを作成するスキーマ名 (既存のもの)"
  type        = string
}

variable "connector_name" {
  description = "作成するコネクタ名 (外から与える)"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z_][A-Za-z0-9_$]*$", var.connector_name))
    error_message = "connector_name は引用符なしで書ける Snowflake 識別子 (英数字・_・$、先頭は英字か _) を指定してください。"
  }
}

variable "runtime_name" {
  description = "コネクタを動かす Runtime 名 (作成済みのもの。modules/snowflake_openflow_runtime の出力を渡すと依存関係になる)"
  type        = string
}

variable "runtime_database" {
  description = "Runtime のあるデータベース名。未指定ならコネクタと同じ"
  type        = string
  default     = null
}

variable "runtime_schema" {
  description = "Runtime のあるスキーマ名。未指定ならコネクタと同じ"
  type        = string
  default     = null
}

variable "definition" {
  description = "コネクタのカタログ定義 ID。PostgreSQL の CDC は OPENFLOW_POSTGRES_CDC"
  type        = string
  default     = "OPENFLOW_POSTGRES_CDC"
}

variable "display_name" {
  description = "コネクタの表示名 (Openflow の UI に出る別名)"
  type        = string
  default     = null
}

variable "comment" {
  description = "コネクタのコメント"
  type        = string
  default     = null
}
