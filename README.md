# fbctf-aws

An **AWS Transform demo kit** for the **legacy "before" state** — the estate
Transform migrates. The modernized target (Fargate, Aurora) is Transform's
output, not this repo's.

| Part | What it is | Deployed? | Cost |
|---|---|---|---|
| **The live app** (`environments/demo`) | [facebookarchive/fbctf](https://github.com/facebookarchive/fbctf) (Hack/HHVM 3.21, nginx, MySQL, memcached — archived 2018) running on AWS | Yes, on demand | ~$5/day up, `$0` destroyed |
| **The simulated estate** (`inventory/`) | A 14-server portfolio as CSV data for the Migration Portfolio Assessment import — the variety a single app can't provide | No — it's data | `$0` |
| **The modernization fixtures** (`modernization/`) | Real .NET Framework, Java 8, COBOL and T-SQL code for Transform's transformation agents | No — source only | `$0` |
| **The estate** (`environments/estate/`) | 12 of those hosts deployed as real, self-terminating EC2 — for pointing Transform at a live account | On demand | ~$4–14/day, self-terminating |

Feature-by-feature coverage and the order to run a full demo:
[`docs/transform-feature-coverage.md`](docs/transform-feature-coverage.md).
Why the demo grew beyond one app: [ADR 004](docs/decisions/004-demo-scope-expansion.md).

Requirements, architecture, validated findings, and the phased implementation plan for the live app live in [`fbctf-aws-requirements.md`](fbctf-aws-requirements.md). Decisions are recorded in [`docs/decisions/`](docs/decisions/); the S3 artifact inventory in [`docs/artifacts-manifest.md`](docs/artifacts-manifest.md).

---

## The live app

### Architecture

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

### Layout

Independent roots, each with its own state key in bucket `fbctf-demo-tfstate-337058058699-use1` (native S3 locking, no DynamoDB):

| Root | State key | Contents |
|---|---|---|
| `environments/demo` | `fbctf-demo/terraform.tfstate` | The live app: network, SGs, IAM, RDS, ElastiCache, NLB/ALB, both ASGs, alarms |
| `environments/artifacts` | `fbctf-artifacts/terraform.tfstate` | The artifacts bucket only — **survives demo destroy cycles** (it holds the insurance against dead upstream repos) |
| `environments/estate` | `fbctf-estate/terraform.tfstate` | The 12-host legacy estate — fully disposable, self-terminating (see [its README](environments/estate/README.md)) |

### Runbook

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

### ⚠️ Destroy discipline

The instances run Ubuntu 16.04 (EOL, unpatched) by design — that's the point of the demo. Do not leave this running unattended. `make destroy` after every session (~$5/day if left up). The artifacts root is not touched by destroy; re-apply brings the scoreboard back in ~20 minutes with the same admin password reachable via Secrets Manager.

---

## The simulated estate

`inventory/` is a 14-server portfolio — Windows/.NET, SQL Server, Java, COBOL,
self-managed services, an idle box — expressed as YAML and turned into the two
CSVs the Migration Portfolio Assessment imports. It costs nothing and is never
deployed.

```sh
python3 -m pip install -r inventory/requirements.txt
python3 inventory/generate.py          # -> inventory/out/*.csv
```

Details, and what each server is there to trigger: [`inventory/README.md`](inventory/README.md).

---

## The modernization fixtures

`modernization/` holds real code for Transform's transformation agents — one
fixture per capability:

| Fixture | Capability |
|---|---|
| [`dotnet-scoreboard/`](modernization/dotnet-scoreboard) | .NET Framework 4.8 → cross-platform .NET |
| [`java-catalog/`](modernization/java-catalog) | Java 8 → 17 |
| [`cobol-rollup/`](modernization/cobol-rollup) | COBOL / mainframe |
| [`sqlserver-schema/`](modernization/sqlserver-schema) | SQL Server → Aurora schema conversion |
| [`atx-task.md`](modernization/atx-task.md) | Transform Custom (`atx`) — generate the target Terraform |

Source only — nothing here is deployed. See [`modernization/README.md`](modernization/README.md).

---

## The estate

`environments/estate/` deploys 12 of the `inventory/` hosts as **real EC2** —
6 Linux (RHEL 7/8, Ubuntu 16.04, Amazon Linux 2), 6 Windows (Server 2016/2019/
2012 R2, SQL Server Express). Each runs its role process under the name the
assessment keys on and chatters to its dependencies. Point Transform at the
account, or import `inventory/out/*.csv`.

Everything is disposable — one destroyable root, nothing that survives destroy,
and every host self-terminates after `max_lifetime_minutes`.

```sh
cp environments/estate/terraform.tfvars.example environments/estate/terraform.tfvars
make apply   ENV=estate                      # enable_windows_tier=false for a ~$4/day Linux-only run
make destroy ENV=estate                      # or let it self-terminate
```

See [`environments/estate/README.md`](environments/estate/README.md).
