terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ---------------------------------------------
# Security Group
# 許可元は allowed_security_group_ids のみ。DB ポートは変数
# Openflow (SPCS) からは DCP エージェントの SG 経由でだけ接続できればよいため、
# 呼び出し側は DCP エージェントの SG を渡す
# ---------------------------------------------

resource "aws_security_group" "this" {
  name        = "${var.name}-aurora"
  description = "Aurora cluster"
  vpc_id      = var.vpc_id

  tags = {
    Name = "${var.name}-aurora"
  }
}

resource "aws_vpc_security_group_ingress_rule" "allowed" {
  count = length(var.allowed_security_group_ids)

  security_group_id            = aws_security_group.this.id
  description                  = "DB from allowed security group"
  ip_protocol                  = "tcp"
  from_port                    = var.port
  to_port                      = var.port
  referenced_security_group_id = var.allowed_security_group_ids[count.index]
}

# ---------------------------------------------
# Subnet Group / Parameter Group
# ---------------------------------------------

resource "aws_db_subnet_group" "this" {
  name       = "${var.name}-aurora"
  subnet_ids = var.subnet_ids

  tags = {
    Name = "${var.name}-aurora"
  }
}

resource "aws_rds_cluster_parameter_group" "this" {
  name        = "${var.name}-aurora"
  family      = var.parameter_group_family
  description = "Aurora cluster parameters (CDC settings)"
  # Openflow に変更 (CDC) を送るための設定を cluster_parameters で受ける。
  # PostgreSQL の rds.logical_replication = 1 がないと、Openflow のコネクタは変更を読み取れない

  dynamic "parameter" {
    for_each = var.cluster_parameters

    content {
      name         = parameter.value.name
      value        = parameter.value.value
      apply_method = parameter.value.apply_method
    }
  }

  tags = {
    Name = "${var.name}-aurora"
  }
}

# ---------------------------------------------
# Aurora クラスタ / インスタンス
# マスターパスワードは Secrets Manager が管理する (state に載らない)
# ---------------------------------------------

resource "aws_rds_cluster" "this" {
  cluster_identifier = "${var.name}-aurora"

  engine         = var.engine
  engine_version = var.engine_version
  port           = var.port

  database_name               = var.database_name
  master_username             = var.master_username
  manage_master_user_password = true

  db_subnet_group_name            = aws_db_subnet_group.this.name
  vpc_security_group_ids          = [aws_security_group.this.id]
  db_cluster_parameter_group_name = aws_rds_cluster_parameter_group.this.name

  storage_encrypted   = true
  skip_final_snapshot = var.skip_final_snapshot
  deletion_protection = var.deletion_protection
  apply_immediately   = true
}

resource "aws_rds_cluster_instance" "this" {
  count = var.instance_count

  identifier         = "${var.name}-aurora-${count.index + 1}"
  cluster_identifier = aws_rds_cluster.this.id
  engine             = aws_rds_cluster.this.engine
  engine_version     = aws_rds_cluster.this.engine_version
  instance_class     = var.instance_class

  db_subnet_group_name       = aws_db_subnet_group.this.name
  publicly_accessible        = false
  auto_minor_version_upgrade = false
  apply_immediately          = true
}
