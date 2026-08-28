# fbctf-aws

Terraform infrastructure for running [facebookarchive/fbctf](https://github.com/facebookarchive/fbctf) (Hack/HHVM 3.21, nginx, MySQL, memcached — archived 2018) on AWS as the **"before" state** for an AWS Transform modernization demo.

Requirements, architecture, validated findings, and the phased implementation plan live in [`fbctf-aws-requirements.md`](fbctf-aws-requirements.md). Decisions are recorded in [`docs/decisions/`](docs/decisions/); the S3 artifact inventory in [`docs/artifacts-manifest.md`](docs/artifacts-manifest.md).

## Architecture

![fbctf on AWS — architecture](assets/fbctf-aws-architecture.png)

<details>
<summary>Text summary</summary>

```
Internet → ALB (HTTP:80, public subnets)
  → nginx ASG (private-app subnets)
    → internal NLB (TCP:9000, FastCGI)
      → HHVM ASG (private-app subnets)
        → RDS MySQL 8.0 + ElastiCache memcached (private-data subnets)
```

</details>

- Account `337058058699` (Sandbox, `cloudcrafters-sandbox` profile with the `AWSTransformAccess` permission set), region `us-east-1` — colocated with the AWS Transform workspace.
- All resource names carry the `fbctf-` prefix — the deploy permission set scopes IAM, S3, and Secrets Manager writes to `fbctf-*`.
- No SSH — instance access via SSM Session Manager only.
- Boot-time provisioning from a pinned, pre-patched app tarball in S3 (ADR 001). Four upstream breakages are patched in the tarball (`scripts/make-source-tarball.sh`).

## Layout

Two independent roots:

| Root | State key | Contents |
|---|---|---|
| `environments/demo` | `fbctf-demo/terraform.tfstate` | Everything destroyable: network, SGs, IAM, RDS, ElastiCache, NLB/ALB, both ASGs, alarms |
| `environments/artifacts` | `fbctf-artifacts/terraform.tfstate` | The artifacts bucket only — **survives demo destroy cycles** (it holds the insurance against dead upstream repos) |

State bucket: `fbctf-demo-tfstate-337058058699-use1` (native S3 locking, no DynamoDB).

## Runbook

```sh
make init
make plan
make apply      # ~12 min of applies; app tier healthy ≈4 min later, web ≈5 min after that
make destroy    # ALWAYS after a demo session — the app runs an EOL OS
```

- **Demo URL**: `alb_dns_name` output. Expect the Facebook CTF login page over plain HTTP.
- **Admin login**: user `admin`; password:
  `aws secretsmanager get-secret-value --secret-id fbctf-demo/admin-password --profile cloudcrafters-sandbox --query SecretString`
- **Shell access**: `aws ssm start-session --target <instance-id> --profile cloudcrafters-sandbox`
- **Boot debugging**: `/var/log/user-data.log` on the instance, also shipped to the `/fbctf/user-data` CloudWatch log group. HHVM errors → `/fbctf/hhvm`; nginx → `/fbctf/nginx`.
- **Alarms** (no actions wired — console-visible only): ALB 5xx, unhealthy hosts on both target groups, RDS CPU/storage.
- **Full rebuild of artifacts** (only needed if the pinned commit or patches change): `scripts/make-source-tarball.sh`, then launch a builder with `scripts/builder-userdata.sh` (see script headers).

### Boot sequence after `make apply`

1. RDS + ElastiCache come up during the apply itself (~7 min).
2. App instance boots: prebuilt tarball → `provision.sh` (hhvm) → settings.ini → guarded DB bootstrap (schema + app user + admin row, one-shot) → HHVM on :9000 → NLB healthy (~4 min).
3. Web instance boots: prebuilt tarball → `provision.sh` (nginx: Node 6, npm, grunt) → HTTP-only site config pointing FastCGI at the NLB → ALB healthy (~5 min).
4. Scoreboard serves at the ALB DNS.

## ⚠️ Destroy discipline

The instances run Ubuntu 16.04 (EOL, unpatched) by design — that's the point of the demo. Do not leave this running unattended. `make destroy` after every session (~$5/day if left up). The artifacts root is not touched by destroy; re-apply brings the scoreboard back in ~20 minutes with the same admin password reachable via Secrets Manager.
