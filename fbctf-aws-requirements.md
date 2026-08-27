# FBCTF on AWS — Infrastructure Requirements Document

**Project:** AWS Transform modernization demo — "before" state application
**App:** facebookarchive/fbctf (Hack/HHVM 3.21, nginx, MySQL, Memcached — archived Sept 2018)
**IaC:** Terraform, boot-time provisioning (no AMI baking)
**Status:** Draft v5 (2026-08-27) — smoke test complete: HHVM 3.21 installs from dl.hhvm.com; MySQL 8.0 import validated; four boot-breaking upstream changes identified and patched into the user-data plan. **Target: Sandbox 337058058699 (`cloudcrafters-sandbox` profile, `AWSTransformAccess` permission set), region us-east-1** — colocated with the AWS Transform workspace for simplicity (Xenial AMI verified there, deprecated — see §3.3). Deploy credentials LIVE (risk #8 resolved) — all resource names MUST use the `fbctf-` prefix. State bucket: `fbctf-demo-tfstate-337058058699-use1` (us-east-1). Phase 0 complete; implementation plan: §8.

---

## 1. Scope and assumptions

- Single AWS region, single environment (`demo`). No DR, no multi-region.
- Demo-grade availability: 2 AZs for network correctness, but single-AZ / minimal instance counts to control cost. The architecture must *look* production-shaped (this is the point of the demo) without paying production bills.
- No AMI baking. Instances self-provision at boot via user-data running the repo's `provision.sh` with `--multiple-servers` flags. An S3 artifacts bucket holds vendored fallbacks (HHVM .debs, app tarball) as insurance against dead upstream repos.
- Phase 1 is HTTP-only at the ALB (no domain/hosted zone yet — decided 2026-08-26). ACM + HTTPS:443 can be added later if a hosted zone materializes. nginx serves plain HTTP internally either way (avoids the app's broken Let's Encrypt path entirely — dl.eff.org no longer resolves).
- No SSH keys and no bastion. All instance access via SSM Session Manager.
- License note: fbctf is CC BY-NC 4.0 (NonCommercial). Sign-off from the demo owner obtained 2026-08-26.
- AWS Transform region note: Transform workspaces cannot be created in us-west-2 (supported: us-east-1, eu-central-1, eu-west-2, ap-south-1, ap-southeast-2, ap-northeast-1, ap-northeast-2, ca-central-1). Decision (2026-08-27): deploy the app in **us-east-1**, colocated with the future Transform workspace, for simplicity. The `AWSTransformAccess` region lockdown already allows us-east-1 alongside us-west-2, so no permission changes were needed.

## 2. Target architecture

```
Internet
  → External ALB (public subnets, HTTP:80 — ACM/443 + Route53 deferred until a hosted zone exists)
      → Web tier: nginx on EC2, ASG (private-app subnets), HTTP:80
          → Internal NLB (TCP:9000)                  ← FastCGI, not HTTP: ALB cannot be used here
              → App tier: HHVM on EC2, ASG (private-app subnets), FastCGI TCP:9000
                  → RDS MySQL 8.0 (private-data subnets, :3306)
                  → ElastiCache Memcached (private-data subnets, :11211)
```

Traffic notes:
- nginx → HHVM is FastCGI over TCP. The internal load balancer MUST be an NLB (L4). An ALB will not work.
- The app reads all endpoints from `settings.ini` (`DB_HOST`, `MC_HOST[]`, ports) — RDS and ElastiCache endpoints are injected there at boot; no code changes required.
- HHVM binds FastCGI on port 9000 to all interfaces (multi-server provisioning comments out `hhvm.server.ip` and the unix socket in hhvm.conf, leaving `hhvm.server.port = 9000` — verified in `extra/lib.sh`).
- Caveat: nginx resolves the NLB DNS name once at config load (`fastcgi_pass <host>:9000` is static). NLB IPs are stable per AZ but can change over time — acceptable for time-boxed demo runs; restart nginx if the app tier becomes unreachable after long uptime.

## 3. Component inventory

### 3.1 Networking
| Component | Spec | Notes |
|---|---|---|
| VPC | 1× /16 (e.g. 10.20.0.0/16) | DNS support + hostnames enabled |
| Public subnets | 2× /24 (2 AZs) | ALB + NAT only |
| Private app subnets | 2× /24 (2 AZs) | nginx tier + HHVM tier |
| Private data subnets | 2× /24 (2 AZs) | RDS + ElastiCache (subnet groups need ≥2 AZs) |
| Internet Gateway | 1 | |
| NAT Gateway | 1 (single, demo cost tradeoff) | Required: boot-time provisioning pulls from archive.ubuntu.com (Xenial is still hosted there — do NOT rewrite sources to old-releases.ubuntu.com, which 404s for xenial), dl.hhvm.com, keyserver.ubuntu.com, getcomposer.org, deb.nodesource.com, registry.npmjs.org, GitHub, S3 |
| Route tables | public ×1, private ×1 (shared, single NAT) | |

### 3.2 Load balancing
| Component | Spec | Notes |
|---|---|---|
| External ALB | internet-facing, public subnets | Listener 80 (HTTP) → TG nginx:80. **Decided: HTTP-only for now** — add 443/ACM later if a hosted zone is created |
| ACM certificate | DEFERRED | No domain/hosted zone yet; revisit when one exists |
| Target group (web) | HTTP:80, health check against a **static asset** (e.g. `/static/img/...` or `/favicon.ico`, expect 200) | `GET /index.php` would transit nginx→NLB→HHVM→RDS, coupling web-tier health to a cold app tier and flapping the web ASG during ~15-min boots. Deregistration delay 30s |
| Internal NLB | private app subnets | Listener TCP:9000 → TG hhvm:9000 |
| Target group (app) | TCP:9000, TCP health check | Cross-zone LB enabled |

### 3.3 Compute
| Component | Spec | Notes |
|---|---|---|
| AMI (both tiers) | Canonical Ubuntu 16.04 Xenial, owner `099720109477`, most recent | Terraform `data "aws_ami"` filter `ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server-*` **with `include_deprecated = true`** — Canonical deprecated these AMIs in 2023 and the data source finds nothing without it. Validated in us-east-1 (2026-08-27): newest is `ami-0b0ea68c435eb488d` (20210928), state `available` (us-west-2 equivalent: `ami-0688ba7eeeeefe3cd`). Frozen/EOL — acceptable for demo, documented risk |
| Web tier launch template + ASG | t3.small, min/desired 1, max 2 | User-data (keep stock apt sources — see §3.1): pull pinned app tarball from S3 → **pre-provision patches (validated 2026-08-26):** (a) NodeSource repo entry with `trusted=yes` or install Node 6.17.1 tarball from nodejs.org — the old signing key no longer verifies and apt refuses `nodejs`; (b) pin `grunt` to `1.0.4` in package.json — no lock file, `^1.0.1` floats to 1.6.x which Node 6 cannot parse; (c) no-op `install_unison` in lib.sh — its rolling Arch URL now serves zstd and `tar Jx` dies under `set -e`; (d) **pin the GLOBAL grunt in provision.sh** (`npm install -g grunt` → `grunt@1.0.4`) and drop `npm install -g flow-bin` — found live during Phase 6 (2026-08-27): the unpinned global install also resolves to 1.6.x and kills provision, a path the smoke test missed because it invoked the local grunt directly; (e) **`src/SessionUtils.php`: `$s_secure = false`** — the session cookie is hardcoded `Secure` (the app was HTTPS-only); over the HTTP-only ALB browsers never send it back, so every login silently bounces to the login page (found live 2026-08-27 during the human gate) → `provision.sh -m prod -R --multiple-servers --server-type nginx --hhvm-server <NLB_DNS>` (provision seds `HHVMSERVER` into nginx.conf itself — no separate fastcgi_pass patch needed) |
| App tier launch template + ASG | t3.medium (Composer needs ≥2 GB RAM) , min/desired 1, max 2 | User-data (keep stock apt sources): pull pinned app tarball from S3 → install HHVM 3.21 (dl.hhvm.com — validated live; fallback S3 .debs) → composer install (validated: installer auto-selects Composer 2.2 LTS, runs under HHVM, lock file resolves) → render `settings.ini` from SSM/Secrets → guarded DB bootstrap (schema import + app DB user + admin row, see 3.6) → `provision.sh -m prod -R --multiple-servers --server-type hhvm --mysql-server <RDS> --cache-server <ElastiCache>` |
| provision.sh mode | `-m prod -R` on both tiers | Default `dev` mode runs `pip install --upgrade pip` on Python 2 (breaks) and hardcodes admin password. `-R` skips HHVM repo-authoritative mode (untested in smoke test; adds boot time/risk for no demo value) |
| Instance metadata | IMDSv2 required | `http_tokens = "required"` |
| EBS | gp3, 20–30 GB, encrypted | |

### 3.4 Data tier
| Component | Spec | Notes |
|---|---|---|
| RDS MySQL | 8.0, db.t3.small, single-AZ, gp3 20 GB, encrypted | **8.0 CONFIRMED** (2026-08-26, mysql:8.0.46): schema.sql + countries.sql + logos.sql import cleanly under stock strict sql_mode; all tables InnoDB/latin1, no zero-date defaults. 5.7 fallback dropped. Not publicly accessible. Deletion protection off (demo), skip_final_snapshot=true |
| RDS parameter group | `sql_mode = NO_ENGINE_SUBSTITUTION` | Precaution for 2018-era runtime queries (import needed none). Auth plugin: HHVM 3.21's client cannot speak `caching_sha2_password` — on **RDS** MySQL 8.0 `default_authentication_plugin` is immutable and already `mysql_native_password` (verified live 2026-08-27), so no parameter needed; the app user is still created `IDENTIFIED WITH mysql_native_password` explicitly in the bootstrap |
| ElastiCache Memcached | cache.t3.micro, 1 node | App supports `MC_HOST[]` array — 1 node is enough for demo |
| DB subnet group / cache subnet group | private data subnets | |

### 3.5 Security groups (least privilege)
| SG | Inbound | From |
|---|---|---|
| `alb` | 443, 80 | 0.0.0.0/0 |
| `web-nginx` | 80 | `alb` SG only |
| `app-hhvm` | 9000 | `web-nginx` SG only (NLB preserves client SG semantics only with client IP preservation off — if issues, source = app-subnet CIDRs) |
| `rds` | 3306 | `app-hhvm` SG only |
| `memcached` | 11211 | `app-hhvm` SG only |
| All | egress 443/80 open | Boot-time provisioning requirement |

### 3.6 Configuration, secrets, and bootstrap data
| Component | Purpose |
|---|---|
| Secrets Manager secret | DB master credentials (generated by Terraform `random_password`, or RDS-managed master password) |
| SSM parameters | `/fbctf/db_endpoint`, `/fbctf/mc_endpoint`, `/fbctf/nlb_dns`, non-secret config |
| S3 artifacts bucket | Versioned, encrypted, private. Contents: app source tarball (pinned commit, **with the three validated patches pre-applied**: NodeSource fix, grunt pin, unison no-op), **vendored HHVM 3.21 .debs**, Node 6.17.1 tarball (nodejs.org), composer.phar, schema SQL files. Improvement option: vendor a fully pre-built tarball (vendor/ + node_modules + grunt output) — cuts app-tier boot from ~15 min to ~5 and removes npm/Packagist from the boot path |
| DB bootstrap strategy | One-time guard: app-tier user-data checks `SELECT 1 FROM configuration LIMIT 1` (validated: `configuration` is seeded by schema.sql, so the guard flips exactly once); if absent, imports `schema.sql` + `countries.sql` + `logos.sql`. **App-tier user-data owns ALL DB bootstrap** — with RDS nothing ever runs `--server-type mysql`, so provision's `import_empty_db`/`set_password` never execute. That includes: create the app DB user `IDENTIFIED WITH mysql_native_password` (real generated credentials, not the repo's `ctf`/`ctf`), and insert the admin team row using `extra/hash.php` under HHVM (available on this tier) |
| Admin password | Generated in user-data, hashed via hash.php, inserted with the admin row; capture into Secrets Manager or set deterministically via SSM parameter |

### 3.7 IAM
| Role/profile | Permissions |
|---|---|
| `ec2-web` instance profile | `AmazonSSMManagedInstanceCore`, S3 read (artifacts bucket), SSM parameters read (`/fbctf/*`) |
| `ec2-app` instance profile | Same + Secrets Manager `GetSecretValue` (DB secret) |
| No IAM users, no access keys | Everything role-based |

### 3.8 Observability and operations
| Component | Spec |
|---|---|
| CloudWatch log groups | `/fbctf/nginx`, `/fbctf/hhvm` (agent optional for demo; at minimum ship `/var/log/hhvm/error.log` — the app's primary debug surface) |
| CloudWatch alarms | ALB 5xx, TG unhealthy hosts, RDS CPU/storage — minimal set |
| SSM Session Manager | Sole shell access path |
| Tags | `Project=fbctf-demo`, `Env=demo`, `Owner`, `ManagedBy=terraform`, `CostCenter` — enforced via provider `default_tags` |

### 3.9 Explicitly out of scope (simplicity)
- AMI baking / Packer (future hardening; noted as the #1 improvement)
- WAF, Shield, GuardDuty, VPC endpoints, multi-AZ RDS, autoscaling policies beyond static counts
- Facebook/Google OAuth (local team auth only — leaves `FACEBOOK_OAUTH_*` / `GOOGLE_OAUTH_FILE` empty)
- CI/CD pipeline for app code (app is frozen; infra pipeline is in scope below)

## 4. Known risks carried into implementation
1. ~~**dl.hhvm.com xenial-lts-3.21 availability**~~ — RESOLVED (smoke test 2026-08-26): repo live, HHVM 3.21.11 installs and runs. Vendored .debs in S3 stay as insurance — the repo could vanish any day.
2. ~~**Xenial apt mirrors**~~ — RESOLVED, and the original mitigation was inverted: `archive.ubuntu.com` still serves Xenial; `old-releases.ubuntu.com` 404s for xenial. User-data must keep stock sources. If Canonical ever moves Xenial, the fallback is the S3-vendored packages, not old-releases.
3. ~~**MySQL 8.0 schema import**~~ — RESOLVED (validated on 8.0.46): clean import under stock strict mode. Residual 8.0 risk is the auth plugin (§3.4) and untested runtime queries — relaxed sql_mode kept as precaution.
4. **Boot-time provisioning fragility** — accepted tradeoff (no AMI baking). Compensations: pinned+patched app tarball in S3, vendored packages, generous ASG health check grace period (≥15 min — composer+grunt on t3 is slow).
5. **EOL OS with no patches** — demo runs should be time-boxed; `terraform destroy` after each session. Note the Xenial AMI itself is deprecated (2023) — launchable, but requires `include_deprecated = true` and could eventually be removed by Canonical.
6. ~~**CC BY-NC 4.0 license**~~ — sign-off obtained 2026-08-26.
7. ~~**State bucket access**~~ — RESOLVED (2026-08-26): dedicated project bucket `fbctf-demo-tfstate-337058058699-use1` in the Sandbox account (us-east-1 as of 2026-08-27), hardened like `create-state-bucket.sh`. (The org's shared `sacm-*` buckets aren't accessible to the demo permission sets; the earlier "explicit deny" reading was partly an artifact of probing with the profile's us-east-1 default region tripping the org's region lockdown.)
8. ~~**Deploy credentials**~~ — RESOLVED (2026-08-26): the `AWSTransformAccess` permission set was extended in cloudlab with fbctf-scoped deploy permissions and is live (verified: CreateVpc dry-run passes; iam:CreateRole denied outside `fbctf-*`, works inside it — canary role+instance profile created and deleted). Deploy via profile `cloudcrafters-sandbox`. **Consequence: every named resource in this project must carry the `fbctf-` prefix** (IAM roles, instance profiles, S3 buckets, secrets — the permission scoping enforces it).
9. ~~**Region lock on the deploy role**~~ — RESOLVED by the account/set switch: `AWSTransformAccess` allows us-west-2 **and us-east-1**. Infra and the future Transform workspace are both us-east-1 (2026-08-27), same account — no cross-region moving parts left.

## 5. Terraform project layout (best-in-class, right-sized)

```
fbctf-aws/
├── README.md                     # Architecture diagram, runbook, destroy instructions
├── .gitignore                    # *.tfstate, .terraform/, *.tfvars (except example)
├── .pre-commit-config.yaml       # terraform fmt, validate, tflint, checkov/trivy
├── .tflint.hcl
├── Makefile                      # make plan/apply/destroy ENV=demo
│
├── environments/
│   └── demo/
│       ├── backend.tf            # S3 backend + state locking
│       ├── providers.tf          # provider + default_tags
│       ├── versions.tf           # terraform >= 1.9, aws ~> 6.0 (pinned)
│       ├── main.tf               # module composition ONLY — no resources
│       ├── variables.tf
│       ├── outputs.tf            # alb_dns_name, rds_endpoint, etc.
│       └── terraform.tfvars.example
│
├── modules/
│   ├── network/                  # VPC, subnets, IGW, NAT, routes
│   │                             # (or wrap terraform-aws-modules/vpc — recommended)
│   ├── security/                 # All SGs + rules, cross-referenced by SG id
│   ├── artifacts/                # S3 bucket, uploads (app tarball, debs, sql)
│   ├── alb-external/             # ALB, listeners, ACM, web target group
│   ├── nlb-internal/             # NLB, TCP listener, app target group
│   ├── service-tier/             # REUSABLE: launch template + ASG + IAM
│   │   ├── main.tf               #   instantiated twice: web + app
│   │   ├── templates/
│   │   │   ├── web-userdata.sh.tpl
│   │   │   └── app-userdata.sh.tpl
│   │   └── ...
│   ├── database/                 # RDS, subnet grp, param grp, secret
│   └── cache/                    # ElastiCache memcached + subnet grp
│
└── docs/
    ├── architecture.md
    └── decisions/                # Lightweight ADRs
        ├── 001-no-ami-baking.md
        ├── 002-nlb-for-fastcgi.md
        └── 003-mysql-version.md
```

### Conventions
- **Remote state:** S3 bucket (versioned, encrypted) with native S3 state locking (`use_lockfile = true`, Terraform ≥1.10) — no DynamoDB table needed anymore. One state per environment. **Decided: dedicated bucket `fbctf-demo-tfstate-337058058699-use1` in Sandbox 337058058699 (`cloudcrafters-sandbox` profile), us-east-1**, hardened like `cloudlab/bootstrap/scripts/create-state-bucket.sh` (versioning, SSE-S3, full public-access block). Key: `fbctf-demo/terraform.tfstate`. The `fbctf-` bucket-name prefix is mandatory — the deploy permission set scopes S3 to `fbctf-*`.
- **Module philosophy:** thin wrappers. Use `terraform-aws-modules/{vpc,alb,autoscaling,rds,security-group}` from the registry inside your modules where they fit — battle-tested beats hand-rolled, and it keeps this fast. Hand-roll only what's fbctf-specific (user-data templates, NLB FastCGI wiring, artifacts).
- **`service-tier` as one reusable module** instantiated twice (web, app) with different user-data templates — this is the professional move vs. copy-pasting two ASG stacks.
- **Pin everything:** Terraform version in `versions.tf`, provider versions with `~>`, registry module versions exactly, app source to a commit SHA.
- **No secrets in state where avoidable:** prefer `manage_master_user_password = true` on RDS (AWS generates + stores in Secrets Manager) so the password never touches Terraform state.
- **user-data discipline:** templates via `templatefile()`, all dynamic values (NLB DNS, RDS endpoint, secret ARN) passed as template vars; scripts idempotent, logging to `/var/log/user-data.log`, `set -euxo pipefail`.
- **Validation gates:** pre-commit runs `terraform fmt -check`, `terraform validate`, `tflint`, and `checkov` (or `trivy config`). Optional GitHub Actions workflow running the same + `terraform plan` on PR.
- **Runbook in README:** exact apply order (single apply — modules handle dependencies via references), expected boot time (~15–20 min for app tier), how to get the admin password, and a prominent `terraform destroy` section (EOL OS should not run unattended).

## 6. Rough monthly cost (us-east-1, running 24/7 — destroy between demos!)
| Item | ~USD/mo |
|---|---|
| 2× EC2 (t3.small + t3.medium) | ~45 |
| ALB + NLB | ~33 |
| NAT Gateway | ~33 + data |
| RDS db.t3.small single-AZ | ~25 |
| ElastiCache t3.micro | ~12 |
| **Total ballpark** | **~150/mo** (≈ $5/day; a 4-hour demo session costs ~$1) |

## 7. Definition of done
- `terraform apply` from zero produces a working scoreboard at the ALB URL within ~20 minutes, admin login functional, level creation + flag capture works end-to-end.
- `terraform destroy` removes everything cleanly (verify no orphaned ENIs/snapshots).
- Smoke-test findings (HHVM source, MySQL version decision) recorded as ADRs 001–003.

## 8. Implementation plan — phased, progressively testable

One root stack (`environments/demo`); each phase lands as a separate commit adding module blocks, so plans stay reviewable and every gate is a real checkpoint. If a gate fails, fix within the phase before stacking the next.

| Phase | Scope | Gate (must pass before next phase) |
|---|---|---|
| **0 — Bootstrap & unblockers** | Create state bucket `fbctf-demo-tfstate-337058058699-use1` (us-east-1, hardened). **IAM canary**: create+delete a tagged throwaway role to settle risk #8 before any IAM code is written. Scaffold §5 repo layout (versions, providers, backend, pre-commit, Makefile, README skeleton) | `terraform init` against the new bucket, `validate`, empty plan all succeed; IAM verdict recorded |
| **1 — Network** | VPC /16, 2-AZ public / private-app / private-data subnets, IGW, single NAT, route tables (wrap `terraform-aws-modules/vpc`) | apply + CLI assertions: subnet counts, NAT route present in private route table |
| **2 — Artifacts** | S3 artifacts bucket + build/upload: patched app tarball (pinned commit + NodeSource fix, grunt→1.0.4 pin, unison no-op), HHVM 3.21 .debs, Node 6.17.1 tarball, composer.phar, SQL files | objects present in S3 with sha256 manifest |
| **3 — Security + IAM** | SG chain (alb→web→app→rds/memcached), instance roles + profiles (shape per Phase 0 IAM verdict) | apply + SG rule assertions via CLI |
| **4 — Data tier** | RDS MySQL 8.0 (param group: relaxed sql_mode + native password plugin), ElastiCache memcached, Secrets Manager + SSM params | temporary SSM-only canary instance in app subnet: mysql connects as native-password user; memcached answers on 11211 |
| **5 — App tier + internal NLB** | `service-tier` module, instantiation #1 (app user-data: HHVM, composer, settings.ini render, guarded DB bootstrap incl. app user + admin row) | via SSM: clean cloud-init log, HHVM listening :9000, FastCGI probe through NLB, guard + admin rows present in RDS |
| **6 — Web tier + external ALB** | `service-tier` instantiation #2 (web user-data with Node/grunt/unison fixes), ALB HTTP:80, static-asset health check | `curl http://<alb-dns>/` serves login page; admin login, level creation, flag capture end-to-end; TG healthy |
| **7 — Ops & DoD** | CloudWatch logs (HHVM error log at minimum), minimal alarms, ADRs 001–003, README runbook | full `terraform destroy` → clean; re-apply from zero → scoreboard in ~20 min (§7) |
