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

`atx` needs `transform-custom:*` (a different service from the `transform:*`
verbs the web app uses). `AWSTransformAccess` **already carries it** — merged to
`aws-access` main as commit `7d8af6b` (`AWSTransformCustomAgent` +
`AWSTransformCustomServiceLinkedRole` on `partner_demo_access`). The `atx` CLI
is installed. Region: `atx` is offered in us-east-1, which the set allows.

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
Deliverable  : the Terraform written into an environments/after/ directory of
               the working copy, terraform fmt + validate clean.
```

## Run

`atx` operates on a **local git working directory** (`-p`), not a clone URL, and
writes changes as **in-place git commits** (committer `ATX Bot`) — it does not
push or open a PR.

```sh
cp -r <modernized .NET 8 output> /tmp/dotnet8
cd /tmp/dotnet8 && git init -q && git add -A && git commit -qm init

# 1. author the definition interactively, pointing atx at this file as reference
AWS_PROFILE=personal-transform AWS_REGION=us-east-1 atx
#   > "create a transformation definition to generate the target Terraform
#   >  described in /…/modernization/atx-task.md; reference that file"
atx custom def save-draft -n fbctf-after-terraform \
  --description "target IaC for the modernized scoreboard" --sd <definition-dir>

# 2. run it
atx custom def exec -n fbctf-after-terraform -p /tmp/dotnet8 -x -t --limit 30
git -C /tmp/dotnet8 diff <first-commit>       # review
```

This is a paid step ($0.035/agent-minute; `--limit` caps it). The assessment and
the standard .NET / mainframe agents and offline schema conversion are all free;
the Java upgrade is the other paid `atx` step.
