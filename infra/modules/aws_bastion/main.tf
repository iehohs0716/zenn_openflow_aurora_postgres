terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Amazon Linux 2023 の最新 AMI (SSM Parameter 経由。SSM Agent はプリインストール済み)
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ---------------------------------------------
# Security Group
# インバウンドなし (接続は SSM Session Manager のみ)。アウトバウンドは SSM への 443、名前解決、DB ポートのみ
# ---------------------------------------------

resource "aws_security_group" "bastion" {
  name        = "${var.name}-bastion"
  description = "Bastion (SSM port forwarding to DB)"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name}-bastion"
  }
}

# SSM / Secrets Manager 宛。SG は FQDN 指定できないため 0.0.0.0/0。実際の出口は NAT Gateway になる
resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.bastion.id
  description       = "HTTPS (SSM)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

# VPC Resolver 宛の名前解決 (Aurora エンドポイントの FQDN 解決)
resource "aws_vpc_security_group_egress_rule" "dns" {
  for_each = toset(["tcp", "udp"])

  security_group_id = aws_security_group.bastion.id
  description       = "DNS (${each.value})"
  ip_protocol       = each.value
  from_port         = 53
  to_port           = 53
  cidr_ipv4         = var.vpc_cidr
}

resource "aws_vpc_security_group_egress_rule" "db_sg" {
  count = length(var.db_security_group_ids)

  security_group_id            = aws_security_group.bastion.id
  description                  = "DB"
  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port
  referenced_security_group_id = var.db_security_group_ids[count.index]
}

# DB 側 SG が未指定の間は VPC 内宛に許可する
resource "aws_vpc_security_group_egress_rule" "db_cidr" {
  count = length(var.db_security_group_ids) == 0 ? 1 : 0

  security_group_id = aws_security_group.bastion.id
  description       = "DB (within VPC CIDR, unused once db_security_group_ids is set)"
  ip_protocol       = "tcp"
  from_port         = var.db_port
  to_port           = var.db_port
  cidr_ipv4         = var.vpc_cidr
}

# ---------------------------------------------
# IAM (SSM Session Manager のみ)
# ---------------------------------------------

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "bastion" {
  name               = "${var.name}-bastion"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.bastion.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "bastion" {
  name = "${var.name}-bastion"
  role = aws_iam_role.bastion.name
}

# ---------------------------------------------
# EC2
# ---------------------------------------------

resource "aws_instance" "bastion" {
  ami                         = data.aws_ssm_parameter.al2023.value
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.bastion.id]
  iam_instance_profile        = aws_iam_instance_profile.bastion.name
  associate_public_ip_address = false

  # IMDSv2 のみ
  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    encrypted = true
  }

  tags = {
    Name = "${var.name}-bastion"
  }
}
