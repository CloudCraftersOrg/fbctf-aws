# Transform Custom (`atx`) task — target Terraform for the modernized scoreboard

The stock .NET agent rewrites `dotnet-scoreboard` source. It does **not** write
the AWS infrastructure the result runs on. That gap is a good Transform Custom
job: a custom agent that reads the modernized project and emits a Terraform
module for its target — the "after" to this repo's "before".

## Cost

Transform Custom bills **$0.035 per agent-minute** while a job runs. A task this
size is a single-digit-dollar job. Nothing is provisioned; the output is a pull
request.

## Prerequisite

`atx` needs `transform-custom:*`, which the `AWSTransformAccess` permission set
does **not** grant today (it has `transform:*` for the web app — a different
service). Add it with an `aws-access` PR before running:

```hcl
# in the AWSTransformAccess inline policy document
statement {
  sid       = "TransformCustomCli"
  effect    = "Allow"
  actions   = ["transform-custom:*"]
  resources = ["*"]
}
```

## Task definition

```
Project root : modernization/dotnet-scoreboard  (post-transformation branch)
Goal         : Produce a Terraform module `environments/after/` that deploys the
               modernized app:
                 - ECS Fargate service, 2 tasks / 2 AZs, ARM64, from an ECR image
                 - Aurora PostgreSQL Serverless v2 (min 0.5 ACU), converted schema
                 - Application Load Balancer, HTTPS via ACM, WAF managed rules
                 - Secrets Manager for the DB credential, injected as a task secret
                 - CloudWatch log group, container insights
                 - all names prefixed fbctf-after-
Constraints  : match this repo's module style (thin wrappers over
               terraform-aws-modules/*), pin every version, no hardcoded account
               IDs, `terraform fmt` + `validate` clean.
Deliverable  : a branch + PR against fbctf-aws with the module and a short
               README diffing before/after cost.
```

## Run

```sh
atx custom job create \
  --name fbctf-after-terraform \
  --repo <clone-url> \
  --instructions atx-task.md \
  --branch modernize/dotnet-8

atx custom job status <job-id>
```

This is the one paid step in the demo. Everything else — the assessment, the
standard code agents, the schema conversion — is covered by the assessment
subscription or is free.
