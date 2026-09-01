# estate — the legacy portfolio as real infrastructure

`inventory/` describes a 14-server estate as CSV for the assessment import.
This root **deploys 12 of those hosts for real** (the 2 fbctf servers stay in
`environments/demo` — don't duplicate that app's provisioning here). Use it when
you want Transform pointed at a live account, or want to RDP/SSH into an actual
legacy box.

Only the **legacy "before" state** is here. The modernized target (Fargate,
Aurora) is Transform's job, not this repo's.

## What it creates

| | |
|---|---|
| VPC | `modules/network` — 10.30.0.0/16, single NAT, all hosts in one AZ (matches the single-AZ resilience finding) |
| Route53 | private zone `corp.local` + an A record per host |
| 6 Linux hosts | `catalog-svc-01` (RHEL 7 / Java 8), `finance-batch-01` (RHEL 8 / GnuCOBOL), `cache-01` (Redis), `mq-01` (Ubuntu 16.04 / RabbitMQ), `nfs-01` (NFS), `ci-01` (Jenkins) |
| 6 Windows hosts | `contoso-web-01` (IIS + ASP.NET), `contoso-app-01/02` (IIS), `contoso-worker-01` (Win 2012 R2), `contoso-sql-01/rpt-01` (SQL Server **Express** — licence-free) — toggle with `enable_windows_tier` |
| IAM | one `fbctf-estate-host` role: SSM core, plus the discovery-agent policy only if `enable_discovery_agent = true` |

Each host's user-data starts its role process under the name the assessment
keys on (`redis-server`, `beam.smp`, `java`, `cobcrun`, `sqlservr`, `w3wp`) and
runs a chatter loop that produces the dependency edges from `hosts.tf`.

## Nothing is preserved

One destroyable root. No bucket that survives destroy, no EIPs, no snapshots, no
key pairs, no CloudWatch log groups. `root_block_device` is
`delete_on_termination`. Every host runs `shutdown +N` at boot and the launch
config terminates on shutdown, so the estate **self-destructs after
`max_lifetime_minutes`** even if `terraform destroy` is skipped.

## Cost

| Config | ~ per hour | ~ per day |
|---|---|---|
| `enable_windows_tier = false` (6 Linux `t3.small`) | ~$0.15 + NAT | ~$4 |
| full (6 Linux + 6 Windows, SQL Express, 1× `t3.medium`) | ~$0.55 + NAT | ~$14 |

Deploying at `fleet.yaml`'s *specced* (deliberately oversized) sizes would be
$200+/day — don't. The right-sizing and TCO findings come from the CSV import;
this estate exists to be discovered and migrated, not to be right-sized.

## Run

```sh
cp environments/estate/terraform.tfvars.example environments/estate/terraform.tfvars
make init  ENV=estate
make apply ENV=estate            # ~10 min; Windows hosts take longer to provision
# ... point Transform at the account, or import ../../inventory/out/*.csv ...
make destroy ENV=estate          # or let it self-terminate
```

## Untested paths

There is no CI on this repo and `apply` was not run pre-merge. Expect iteration
on first apply, especially:

- deprecated AMI lookups (`ubuntu-xenial`, `windows-2012-r2`, `rhel7`) — Canonical
  / AWS / Red Hat may have removed them; the matching host then fails at launch
- Windows user-data (IIS site creation, SQL Express TCP enable) is best-effort
- `w3wp` only appears once the warm-up task has made a request

`terraform fmt`, `validate` and `tflint` pass.
