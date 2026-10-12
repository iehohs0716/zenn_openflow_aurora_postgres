variable "database" {
  description = "シークレットを作る既存のデータベース名 (作成しない。引用符なしで書ける名前。Snowflake 上では大文字になる)"
  type        = string
}

variable "schema" {
  description = "シークレットを作る既存のスキーマ名 (作成しない。引用符なしで書ける名前。Snowflake 上では大文字になる)"
  type        = string
}

variable "name" {
  description = "シークレット名 (引用符なしで書ける名前。Snowflake 上では大文字になる)"
  type        = string
}

variable "comment" {
  description = "シークレットのコメント"
  type        = string
  default     = null
}

variable "read_roles" {
  description = "シークレットの READ を付与するロール名のリスト (Runtime の実行ロールなど)"
  type        = list(string)
  default     = []
}
