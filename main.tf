resource "random_string" "sfx" {
  count   = var.add_random_suffix ? 1 : 0
  length  = var.random_suffix_length
  upper   = false
  lower   = true
  numeric = true
  special = false
}


locals {
  # normalize without regex: lower + replace common bad chars with '-'
  user_suffix_base  = lower(trimspace(var.name_suffix))
  user_suffix_clean = replace(
    replace(
      replace(
        replace(
          replace(local.user_suffix_base, " ", "-"),
        "_", "-"),
      ".", "-"),
    "/", "-"),
  ":", "-")

  random_part = var.add_random_suffix ? random_string.sfx[0].result : ""
  suffix_raw  = trim(join("-", compact([local.user_suffix_clean, local.random_part])), "-")
  suffix      = length(local.suffix_raw) > 0 ? "-${local.suffix_raw}" : ""

  common_tags = merge({ Project = "rdi-provider-rds" }, var.tags)
}

# --- Look up NLB subnets to derive their CIDRs for SG rules ---
data "aws_subnet" "nlb" {
  for_each = toset(var.nlb_subnet_ids)
  id       = each.value
}

locals {
  nlb_cidrs = [for s in data.aws_subnet.nlb : s.cidr_block]
}

# --- Security Group for RDS: allow TCP/5432 from NLB subnets (and optional CIDRs) ---
resource "aws_security_group" "rds" {
  name        = "rdi-rds-pg-sg${local.suffix}"
  description = "Allow PostgreSQL from NLB subnets and optional CIDRs"
  vpc_id      = var.vpc_id
  tags        = local.common_tags
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_nlb_cidrs" {
  for_each          = toset(local.nlb_cidrs)
  security_group_id = aws_security_group.rds.id
  cidr_ipv4         = each.value
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"
  description       = "PostgreSQL from NLB subnet"
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_extra_cidrs" {
  for_each          = toset(var.extra_allowed_cidrs_to_db)
  security_group_id = aws_security_group.rds.id
  cidr_ipv4         = each.value
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"
  description       = "PostgreSQL from extra CIDR"
}

resource "aws_vpc_security_group_egress_rule" "rds_all_egress" {
  security_group_id = aws_security_group.rds.id
  cidr_ipv4         = "0.0.0.0/0"
  ip_protocol       = "-1"
}

# --- DB Subnet Group ---
resource "aws_db_subnet_group" "db" {
  name       = "rdi-rds-pg-subnets${local.suffix}"
  subnet_ids = var.db_subnet_ids
  tags       = local.common_tags
}

# --- DB Parameter Group: PostgreSQL 17 with logical replication enabled ---
resource "aws_db_parameter_group" "pg17_rdi" {
  name        = "rdi-pg17${local.suffix}"
  family      = "postgres17"
  description = "rdi-pg17 parameter group with logical replication enabled${local.suffix}"
  tags        = local.common_tags

  parameter {
    name         = "rds.logical_replication"
    value        = "1"
    apply_method = "pending-reboot" # static param -> requires reboot
  }
}

# --- RDS PostgreSQL (Single-AZ, Private) ---
resource "aws_db_instance" "pg" {
  identifier                = substr("rdi-rds-pg${local.suffix}", 0, 63)
  engine                    = "postgres"
  engine_version            = var.engine_version
  instance_class            = var.db_instance_class
  allocated_storage         = var.db_allocated_storage
  db_name                   = var.db_name
  username                  = var.db_username
  password                  = var.db_password
  db_subnet_group_name      = aws_db_subnet_group.db.name
  vpc_security_group_ids    = [aws_security_group.rds.id]
  multi_az                  = false
  publicly_accessible       = false
  storage_encrypted         = true
  delete_automated_backups  = true
  deletion_protection       = false
  skip_final_snapshot       = true

  # disable enhanced monitoring to avoid extra costs
  monitoring_interval       = 0

  # attach the custom parameter group & apply ASAP
  parameter_group_name = aws_db_parameter_group.pg17_rdi.name
  apply_immediately    = true

  tags = local.common_tags
}

# --- NLB (internal) ---
resource "aws_lb" "nlb" {
  name               = substr("rdi-rds-nlb${local.suffix}", 0, 32)
  internal           = true
  load_balancer_type = "network"
  ip_address_type    = "ipv4"
  subnets            = var.nlb_subnet_ids
  tags               = local.common_tags
}

# --- Target Group (IP targets -> resolved RDS endpoint private IP) ---
resource "aws_lb_target_group" "tg" {
  name        = substr("rdi-rds-tg${local.suffix}", 0, 32)
  port        = 5432
  protocol    = "TCP"
  vpc_id      = var.vpc_id
  target_type = "ip"

  health_check {
    protocol = "TCP"
    port     = "5432"
  }

  tags = local.common_tags
}

# Resolve the RDS DNS -> private IP at apply time (must run where private DNS resolves)
data "external" "rds_ip" {
  depends_on = [aws_db_instance.pg]
  program    = [
    "python3", "-c",
    "import socket, json, sys; print(json.dumps({'ip': socket.gethostbyname(sys.argv[1])}))",
    aws_db_instance.pg.address
  ]
}

resource "aws_lb_target_group_attachment" "rds_ip" {
  target_group_arn = aws_lb_target_group.tg.arn
  target_id        = data.external.rds_ip.result.ip
  port             = 5432
}

# --- Listener (TCP 5432) ---
resource "aws_lb_listener" "nlb_5432" {
  load_balancer_arn = aws_lb.nlb.arn
  port              = 5432
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg.arn
  }
}

# --- Endpoint Service (PrivateLink) ---
resource "aws_vpc_endpoint_service" "svc" {
  acceptance_required        = true
  network_load_balancer_arns = [aws_lb.nlb.arn]
  supported_ip_address_types = ["ipv4"]
  private_dns_name           = null
  tags                       = local.common_tags
}

resource "aws_vpc_endpoint_service_allowed_principal" "rdi" {
  vpc_endpoint_service_id = aws_vpc_endpoint_service.svc.id
  principal_arn           = var.rdi_endpoint_service_principal_arn
}

# --- KMS Key (for Secrets Manager encryption) ---
data "aws_caller_identity" "current" {}

resource "aws_kms_key" "rdi" {
  description         = "KMS key for RDI DB credentials secret"
  enable_key_rotation = true

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      # Admin in this account
      {
        Sid      = "EnableRootAdmin",
        Effect   = "Allow",
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" },
        Action   = "kms:*",
        Resource = "*"
      },
      # Allow RDI ACCOUNT ROOT to use this key (Encrypt/Decrypt/Describe etc.)
      {
        Sid      = "AllowRDIAccountUseKey",
        Effect   = "Allow",
        Principal = { AWS = "arn:aws:iam::${var.rdi_account_id}:root" },
        Action   = [
          "kms:Encrypt",
          "kms:Decrypt",
          "kms:DescribeKey",
          "kms:ReEncrypt*",
          "kms:GenerateDataKey*"
        ],
        Resource = "*"
      }
    ]
  })

  tags = local.common_tags
}

resource "aws_kms_alias" "rdi" {
  name          = "alias/rdi-rds-secrets${local.suffix}"
  target_key_id = aws_kms_key.rdi.key_id
}

# --- Secrets Manager: Credentials (username/password) ---
resource "aws_secretsmanager_secret" "db_credentials" {
  name       = "rdi-rds-db-credentials${local.suffix}"
  kms_key_id = aws_kms_key.rdi.arn
  tags       = local.common_tags
}

resource "aws_secretsmanager_secret_version" "db_credentials_val" {
  secret_id     = aws_secretsmanager_secret.db_credentials.id
  secret_string = jsonencode({
    username = var.db_username
    password = var.db_password
  })
}

# Resource policy so RDI can Get/Describe the secret (Principal "*" with aws:PrincipalArn condition)
resource "aws_secretsmanager_secret_policy" "db_credentials" {
  secret_arn = aws_secretsmanager_secret.db_credentials.arn
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Sid       = "RedisDataIntegrationRoleAccess",
      Effect    = "Allow",
      Principal = "*",
      Action    = ["secretsmanager:GetSecretValue", "secretsmanager:DescribeSecret"],
      Resource  = "*",
      Condition = {
        StringLike = {
          "aws:PrincipalArn" = var.rdi_secret_access_principal_arn
        }
      }
    }]
  })
}

# --- Reboot DB after parameter change (static param) ---
#resource "null_resource" "reboot_after_param_change" {
#  triggers = {
#    instance_id          = aws_db_instance.pg.id
#    parameter_group_name = aws_db_instance.pg.parameter_group_name
#  }
#
#  provisioner "local-exec" {
#    command = "aws rds reboot-db-instance --db-instance-identifier ${aws_db_instance.pg.id} --region ${var.region}"
#  }
#}