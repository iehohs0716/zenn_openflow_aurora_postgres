variable "name" {
  description = "シークレット名"
  type        = string
}

variable "description" {
  description = "シークレットの説明"
  type        = string
  default     = ""
}

variable "recovery_window_in_days" {
  description = "削除後の復旧待機期間 (日)。0 なら即時削除され、destroy 後すぐ同名で再作成できる (PoC 向け)。本番では 7〜30 を推奨"
  type        = number
  default     = 0
}
