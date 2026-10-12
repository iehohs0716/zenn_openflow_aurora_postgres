terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# Amazon Linux 2023 の最新 AMI (SSM Parameter 経由)
data "aws_ssm_parameter" "al2023" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

data "aws_region" "current" {}

# ---------------------------------------------
# Security Group
# インバウンドなし。アウトバウンドは Snowflake 等への 443、名前解決、DB ポートのみ
# ---------------------------------------------

resource "aws_security_group" "agent" {
  name        = "${var.name}-dcp-agent"
  description = "DCP agent"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name}-dcp-agent"
  }
}

# Snowflake / Docker Hub / SSM / Secrets Manager / dnf リポジトリ宛。SG は FQDN 指定できないため 0.0.0.0/0
# 実際の出口は NAT Gateway になる
resource "aws_vpc_security_group_egress_rule" "https" {
  security_group_id = aws_security_group.agent.id
  description       = "HTTPS (Snowflake DCP, Docker Hub, SSM, Secrets Manager, dnf)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

# VPC Resolver 宛の名前解決 (Aurora エンドポイントの FQDN 解決)
resource "aws_vpc_security_group_egress_rule" "dns" {
  for_each = toset(["tcp", "udp"])

  security_group_id = aws_security_group.agent.id
  description       = "DNS (${each.value})"
  ip_protocol       = each.value
  from_port         = 53
  to_port           = 53
  cidr_ipv4         = var.vpc_cidr
}

# DB への接続 (DCP は TCP パススルー)
resource "aws_vpc_security_group_egress_rule" "db_sg" {
  count = length(var.db_security_group_ids)

  security_group_id            = aws_security_group.agent.id
  description                  = "DB (DCP tunnel destination)"
  ip_protocol                  = "tcp"
  from_port                    = var.db_port
  to_port                      = var.db_port
  referenced_security_group_id = var.db_security_group_ids[count.index]
}

# DB 側 SG が未指定の間 (Aurora モジュール作成前) は VPC 内宛に許可する
resource "aws_vpc_security_group_egress_rule" "db_cidr" {
  count = length(var.db_security_group_ids) == 0 ? 1 : 0

  security_group_id = aws_security_group.agent.id
  description       = "DB (within VPC CIDR, unused once db_security_group_ids is set)"
  ip_protocol       = "tcp"
  from_port         = var.db_port
  to_port           = var.db_port
  cidr_ipv4         = var.vpc_cidr
}

resource "aws_vpc_security_group_ingress_rule" "metrics" {
  for_each = toset(var.metrics_cidr_blocks)

  security_group_id = aws_security_group.agent.id
  description       = "Prometheus metrics"
  ip_protocol       = "tcp"
  from_port         = 9092
  to_port           = 9092
  cidr_ipv4         = each.value
}

# ---------------------------------------------
# IAM (SSM Session Manager + Secrets Manager のトークン読み取り。シークレットは外から受け取る)
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

resource "aws_iam_role" "agent" {
  name               = "${var.name}-dcp-agent"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.agent.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "token" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.bootstrap_token_secret_arn]
  }
}

resource "aws_iam_role_policy" "token" {
  name   = "read-bootstrap-token"
  role   = aws_iam_role.agent.id
  policy = data.aws_iam_policy_document.token.json
}

resource "aws_iam_instance_profile" "agent" {
  name = "${var.name}-dcp-agent"
  role = aws_iam_role.agent.name
}

# ---------------------------------------------
# EC2
# ---------------------------------------------

resource "aws_instance" "agent" {
  count = var.instance_count

  ami                         = data.aws_ssm_parameter.al2023.value
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_ids[count.index % length(var.subnet_ids)]
  vpc_security_group_ids      = [aws_security_group.agent.id]
  iam_instance_profile        = aws_iam_instance_profile.agent.name
  associate_public_ip_address = false

  # IMDSv2 のみ
  metadata_options {
    http_tokens   = "required"
    http_endpoint = "enabled"
  }

  root_block_device {
    encrypted = true
  }

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    region      = data.aws_region.current.name
    secret_id   = var.bootstrap_token_secret_name
    agent_image = var.agent_image
  })
  user_data_replace_on_change = true

  tags = {
    Name = "${var.name}-dcp-agent-${count.index + 1}"
  }
}
