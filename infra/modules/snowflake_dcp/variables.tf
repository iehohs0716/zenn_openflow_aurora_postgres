variable "name" {
  description = "DCP オブジェクト名 (CREATE DATA CONNECTIVITY PROXY で作成する)"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z_][A-Za-z0-9_$]*$", var.name))
    error_message = "name は引用符なしで書ける Snowflake 識別子 (英数字・_・$、先頭は英字か _) を指定してください。"
  }
}

variable "database" {
  description = "ネットワークルールを作成するデータベース名 (既存のもの)"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z_][A-Za-z0-9_$]*$", var.database))
    error_message = "database は引用符なしで書ける Snowflake 識別子を指定してください。"
  }
}

variable "schema" {
  description = "ネットワークルールを作成するスキーマ名 (既存のもの)"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z_][A-Za-z0-9_$]*$", var.schema))
    error_message = "schema は引用符なしで書ける Snowflake 識別子を指定してください。"
  }
}

variable "network_rule_name" {
  description = "ネットワークルール名"
  type        = string
  default     = "DCP_AURORA_RULE"

  validation {
    condition     = can(regex("^[A-Za-z_][A-Za-z0-9_$]*$", var.network_rule_name))
    error_message = "network_rule_name は引用符なしで書ける Snowflake 識別子を指定してください。"
  }
}

variable "eai_name" {
  description = "External Access Integration 名"
  type        = string
  default     = "DCP_AURORA_EAI"

  validation {
    condition     = can(regex("^[A-Za-z_][A-Za-z0-9_$]*$", var.eai_name))
    error_message = "eai_name は引用符なしで書ける Snowflake 識別子を指定してください。"
  }
}

variable "target_host" {
  description = "接続先の FQDN (Aurora ライター(クラスタ)エンドポイント)。IP アドレスは不可"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$", var.target_host)) && !can(regex("^[0-9.]+$", var.target_host))
    error_message = "target_host は FQDN を指定してください (IP アドレスや記号は不可)。"
  }
}

variable "target_port" {
  description = "接続先のポート (PostgreSQL は 5432、MySQL は 3306)"
  type        = number

  validation {
    condition     = var.target_port >= 1 && var.target_port <= 65535
    error_message = "target_port は 1〜65535 を指定してください。"
  }
}
