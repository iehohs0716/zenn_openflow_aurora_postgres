variable "database" {
  description = "Openflow が使うデータベース名 (既存のもの)。Runtime / コネクタの作成先で、コネクタの宛先でもある"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z_][A-Za-z0-9_$]*$", var.database))
    error_message = "database は引用符なしで書ける Snowflake 識別子を指定してください。"
  }
}

variable "schema" {
  description = "Runtime / コネクタを作成するスキーマ名 (既存のもの)"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z_][A-Za-z0-9_$]*$", var.schema))
    error_message = "schema は引用符なしで書ける Snowflake 識別子を指定してください。"
  }
}

variable "warehouse" {
  description = "コネクタが MERGE に使うウェアハウス名 (既存のもの)。作成はしない"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z_][A-Za-z0-9_$]*$", var.warehouse))
    error_message = "warehouse は引用符なしで書ける Snowflake 識別子を指定してください。"
  }
}

variable "admin_role_name" {
  description = "Openflow の Runtime / コネクタを操作するロール名。公式の手順が OPENFLOW_ADMIN を使う"
  type        = string
  default     = "OPENFLOW_ADMIN"

  validation {
    condition     = can(regex("^[A-Za-z_][A-Za-z0-9_$]*$", var.admin_role_name))
    error_message = "admin_role_name は引用符なしで書ける Snowflake 識別子を指定してください。"
  }
}

variable "runtime_role_name" {
  description = "Runtime の EXECUTE_AS_ROLE に指定するロール名 (コネクタが宛先への書き込みに使う)"
  type        = string
  default     = "OPENFLOW_RUNTIME_ROLE"

  validation {
    condition     = can(regex("^[A-Za-z_][A-Za-z0-9_$]*$", var.runtime_role_name))
    error_message = "runtime_role_name は引用符なしで書ける Snowflake 識別子を指定してください。"
  }
}

variable "admin_granted_to_roles" {
  description = "OPENFLOW_ADMIN を付与するロール。Terraform / スクリプトの実行ロール (.env の SNOWFLAKE_ROLE) を含める"
  type        = list(string)
}
