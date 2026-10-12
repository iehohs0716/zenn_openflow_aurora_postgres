variable "deployment_name" {
  description = "Runtime を作成する Openflow の Deployment 名 (Snowflake Deployment)"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z_][A-Za-z0-9_$]*$", var.deployment_name))
    error_message = "deployment_name は引用符なしで書ける Snowflake 識別子を指定してください。"
  }
}

variable "database" {
  description = "Runtime を作成するデータベース名 (既存のもの)"
  type        = string
}

variable "schema" {
  description = "Runtime を作成するスキーマ名 (既存のもの)"
  type        = string
}

variable "runtime_name" {
  description = "作成する Runtime 名"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z_][A-Za-z0-9_$]*$", var.runtime_name))
    error_message = "runtime_name は引用符なしで書ける Snowflake 識別子を指定してください。"
  }
}

variable "execute_as_role" {
  description = "Runtime の実行ロール名 (事前に作成済みのもの。modules/snowflake_openflow_roles)"
  type        = string
}

variable "external_access_integrations" {
  description = "Runtime に付与する External Access Integration 名 (DCP 用 EAI など)。実行ロールに USAGE も付与する"
  type        = list(string)
  default     = []
}

variable "node_type" {
  description = "Runtime のノードの種類 (SMALL / MEDIUM / LARGE)。PoC は SMALL"
  type        = string
  default     = "SMALL"
}

variable "min_nodes" {
  description = "Runtime の最小ノード数"
  type        = number
  default     = 1
}

variable "max_nodes" {
  description = "Runtime の最大ノード数"
  type        = number
  default     = 1
}
