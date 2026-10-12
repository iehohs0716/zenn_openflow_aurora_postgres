variable "name" {
  description = "リソース名のプレフィックス (VPC名)"
  type        = string
}

variable "vpc_cidr" {
  description = "VPC の CIDR ブロック"
  type        = string
}

variable "availability_zones" {
  description = "使用するAZのリスト"
  type        = list(string)
}

variable "public_subnet_cidrs" {
  description = "パブリックサブネットの CIDR (availability_zones と同数)"
  type        = list(string)
}

variable "private_subnet_cidrs" {
  description = "プライベートサブネットの CIDR (availability_zones と同数)"
  type        = list(string)
}

variable "enable_nat_gateway" {
  description = "NAT Gateway (1台、先頭のパブリックサブネットに配置) を作成するか"
  type        = bool
  default     = true
}
