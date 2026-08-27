# Instance roles + profiles for the two EC2 tiers (§3.7). Role names must be
# fbctf-* — the deploy permission set scopes IAM writes and PassRole to that
# prefix. Both tiers get SSM Session Manager, artifacts-bucket read, /fbctf/*
# SSM parameter read, and CloudWatch Logs write; only the app tier can read
# the DB secrets.

data "aws_caller_identity" "this" {}
data "aws_partition" "this" {}
data "aws_region" "this" {}

locals {
  tiers = {
    web = { secrets_access = false }
    app = { secrets_access = true }
  }

  param_arn_prefix = "arn:${data.aws_partition.this.partition}:ssm:${data.aws_region.this.region}:${data.aws_caller_identity.this.account_id}:parameter/fbctf/*"
  logs_arn_prefix  = "arn:${data.aws_partition.this.partition}:logs:${data.aws_region.this.region}:${data.aws_caller_identity.this.account_id}:log-group:/fbctf/*"
  secret_arns = [
    "arn:${data.aws_partition.this.partition}:secretsmanager:${data.aws_region.this.region}:${data.aws_caller_identity.this.account_id}:secret:fbctf-*",
    "arn:${data.aws_partition.this.partition}:secretsmanager:${data.aws_region.this.region}:${data.aws_caller_identity.this.account_id}:secret:rds!*",
  ]
}

data "aws_iam_policy_document" "assume_ec2" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "tier" {
  for_each = local.tiers

  name               = "${var.name}-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.assume_ec2.json
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  for_each = local.tiers

  role       = aws_iam_role.tier[each.key].name
  policy_arn = "arn:${data.aws_partition.this.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "tier" {
  for_each = local.tiers

  statement {
    sid       = "ArtifactsRead"
    actions   = ["s3:GetObject", "s3:ListBucket"]
    resources = [var.artifacts_bucket_arn, "${var.artifacts_bucket_arn}/*"]
  }

  statement {
    sid       = "FbctfParamsRead"
    actions   = ["ssm:GetParameter", "ssm:GetParameters", "ssm:GetParametersByPath"]
    resources = [local.param_arn_prefix]
  }

  statement {
    sid       = "FbctfLogsWrite"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents", "logs:DescribeLogStreams"]
    resources = ["${local.logs_arn_prefix}:*"]
  }

  dynamic "statement" {
    for_each = each.value.secrets_access ? [1] : []

    content {
      sid       = "DbSecretsRead"
      actions   = ["secretsmanager:GetSecretValue"]
      resources = local.secret_arns
    }
  }
}

resource "aws_iam_role_policy" "tier" {
  for_each = local.tiers

  name   = "${var.name}-${each.key}"
  role   = aws_iam_role.tier[each.key].id
  policy = data.aws_iam_policy_document.tier[each.key].json
}

resource "aws_iam_instance_profile" "tier" {
  for_each = local.tiers

  name = "${var.name}-${each.key}"
  role = aws_iam_role.tier[each.key].name
}
