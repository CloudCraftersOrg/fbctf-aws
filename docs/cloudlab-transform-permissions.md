# cloudlab change: fbctf deploy permissions for the Transform cohort

Target: `terraform/data.tf`, data source `sso_aws_transform_access` (the inline
policy behind the `AWSTransformAccess` permission set). No changes needed in
`variables.tf` grants — the set is already assigned to the AWSTransform group on
the Sandbox account (337058058699). Optionally update the set's `description`.

Paste the statements below **before the closing `}`** of
`data "aws_iam_policy_document" "sso_aws_transform_access"` (after the
`AWSTransformWebAppAccess` statement). Then `terraform fmt` + `validate`.

```hcl
  # ── fbctf demo infrastructure (added 2026-08) ────────────────────────────
  # The cohort deploys the legacy fbctf app — the "before" state the Transform
  # demo modernizes — into the Sandbox account with Terraform: VPC, ALB + NLB,
  # two EC2 Auto Scaling tiers, RDS MySQL and ElastiCache. Service-wide allows
  # are acceptable here because this permission set is region-locked
  # (us-west-2/us-east-1), granted only to the three-person cohort, and the
  # sensitive edges — IAM, S3, Secrets Manager — are name-scoped to fbctf-*
  # in the statements that follow.
  statement {
    sid    = "FbctfInfraDeploy"
    effect = "Allow"
    actions = [
      "autoscaling:*",
      "cloudwatch:*",
      "ec2:*",
      "elasticache:*",
      "elasticloadbalancing:*",
      "kms:DescribeKey",
      "kms:ListAliases",
      "logs:*",
      "rds:*",
      "ssm:*",
    ]
    resources = ["*"]
  }

  # Terraform state bucket plus the demo's artifacts bucket. Everything the
  # project touches in S3 is named fbctf-*; s3:* here also covers creating
  # the buckets themselves.
  statement {
    sid     = "FbctfS3"
    effect  = "Allow"
    actions = ["s3:*"]
    resources = [
      "arn:aws:s3:::fbctf-*",
      "arn:aws:s3:::fbctf-*/*",
    ]
  }

  # Instance roles / profiles for the two EC2 tiers. Writes are name-scoped
  # below; reads are account-wide because terraform refresh resolves AWS
  # managed policies and service roles outside the fbctf-* prefix.
  statement {
    sid       = "FbctfIamRead"
    effect    = "Allow"
    actions   = ["iam:Get*", "iam:List*"]
    resources = ["*"]
  }

  statement {
    sid    = "FbctfIamWriteScoped"
    effect = "Allow"
    actions = [
      "iam:AddRoleToInstanceProfile",
      "iam:AttachRolePolicy",
      "iam:CreateInstanceProfile",
      "iam:CreateRole",
      "iam:DeleteInstanceProfile",
      "iam:DeleteRole",
      "iam:DeleteRolePolicy",
      "iam:DetachRolePolicy",
      "iam:PutRolePolicy",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:TagInstanceProfile",
      "iam:TagRole",
      "iam:UntagInstanceProfile",
      "iam:UntagRole",
    ]
    resources = [
      "arn:aws:iam::*:role/fbctf-*",
      "arn:aws:iam::*:instance-profile/fbctf-*",
    ]
  }

  # Attach the fbctf instance profiles at launch — EC2 only, fbctf roles only.
  statement {
    sid       = "FbctfIamPassRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::*:role/fbctf-*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["ec2.amazonaws.com"]
    }
  }

  # The first `terraform apply` in a fresh account creates the service-linked
  # roles for the load balancers, Auto Scaling, RDS and ElastiCache.
  statement {
    sid       = "FbctfServiceLinkedRoles"
    effect    = "Allow"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values = [
        "autoscaling.amazonaws.com",
        "elasticache.amazonaws.com",
        "elasticloadbalancing.amazonaws.com",
        "rds.amazonaws.com",
      ]
    }
  }

  # DB credentials: the project's own secrets plus the RDS-managed master
  # secret (RDS names it rds!... when manage_master_user_password is used).
  statement {
    sid     = "FbctfSecrets"
    effect  = "Allow"
    actions = ["secretsmanager:*"]
    resources = [
      "arn:aws:secretsmanager:*:*:secret:fbctf-*",
      "arn:aws:secretsmanager:*:*:secret:rds!*",
    ]
  }
```

Optional, `terraform/variables.tf` — keep the description honest:

```hcl
    AWSTransformAccess = {
      description       = "AWS Transform demo cohort: web app sign-in plus deploying the fbctf demo app"
      inline_policy_key = "sso_aws_transform_access"
      allowed_regions   = ["us-west-2", "us-east-1"]
    }
```

Also consider amending the header comment above `sso_aws_transform_access`
("...the cohort needs no ec2/s3/rds permissions either") — the Fbctf*
statements are now the deliberate exception.

Notes:
- Everything the fbctf Terraform names must use the `fbctf-` prefix (roles,
  instance profiles, buckets, secrets) or it will hit the scoped denials.
- After merge + CI apply, re-login (`aws sso login --sso-session cloudcrafters`)
  and use profile `cloudcrafters-sandbox` with
  `sso_role_name = AWSTransformAccess` and `region = us-west-2`.

## Optional — only if reusing `sacm-sandbox-tfstate` instead of a new bucket

The plan is a NEW bucket (`fbctf-demo-tfstate-337058058699`), which the
`FbctfS3` statement above already fully covers — creating it included. Skip
this section in that case.

If the org would rather keep one state bucket per account, add this statement
too: it grants state read/write on `sacm-sandbox-tfstate` restricted to the
`fbctf-demo/` key prefix, so the cohort cannot touch the org bootstrap state
stored in the same bucket.

```hcl
  # fbctf Terraform state in the account's shared state bucket, restricted to
  # the fbctf-demo/ prefix (the bucket also holds org bootstrap state).
  statement {
    sid       = "FbctfSharedStateBucketList"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::sacm-sandbox-tfstate"]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["fbctf-demo/*", "fbctf-demo", ""]
    }
  }

  statement {
    sid       = "FbctfSharedStateBucketMeta"
    effect    = "Allow"
    actions   = ["s3:GetBucketLocation", "s3:GetBucketVersioning"]
    resources = ["arn:aws:s3:::sacm-sandbox-tfstate"]
  }

  statement {
    sid       = "FbctfSharedStateObjects"
    effect    = "Allow"
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::sacm-sandbox-tfstate/fbctf-demo/*"]
  }
```

(`s3:DeleteObject` is required by Terraform >= 1.10 native S3 locking — it
creates and deletes a `.tflock` object next to the state key. The bucket-meta
actions are split out because they are not prefix-conditionable.)
