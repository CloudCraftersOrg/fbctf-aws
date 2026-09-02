# discovery-collector — run the real AWS Transform discovery tool

`inventory/` gives Transform an assessment ZIP built from asserted data.
**This env runs the actual tool** — the Linux installer on one EC2 host — and
lets it **SSH / WinRM into live servers** to collect genuine inventory,
CPU/RAM/disk metrics, running processes, netstat dependencies and database
metadata, then export `discovery_tool_export.zip` for the migration assessment.
The last export it produced is committed at
[`inventory/discovery-tool-export/`](../../inventory/discovery-tool-export).

## What it creates

| | |
|---|---|
| VPC `10.70.0.0/16` + public subnet | peered to the `sqlmod` VPC (`discover_sqlmod`) and the `oramod` VPC (`discover_oramod`), both default on |
| Collector | `t3.xlarge` (4 vCPU / 16 GB — the tool's minimum), Amazon Linux 2023; user-data installs `AWS-Transform-discovery-tool.sh` and stages the import CSV + SSH key |
| Fleet | 6 × `t3.small` — `catalog-svc-01` (Java 8), `finance-batch-01` (COBOL), `cache-01` (Redis), `mq-01` (RabbitMQ), `nfs-01` (NFS), `ci-01` (Jenkins) — real role processes + inter-node chatter for the dependency graph |
| Windows | 1 × `t3.small`, **Windows Server 2022 + SQL Server 2022 Express** (`enable_windows`, default on) — WinRM HTTPS + a `discovery` local admin, IIS (`w3wp`), SQL on 1433. Exercises the tool's WinRM path, **SQL Server module**, and Windows OS discovery. Creds in `terraform output -json windows_target`. |
| Peering | VPC peering + routes into `fbctf-sqlmod` and `fbctf-oramod`. Those roots open SSH / WinRM / Oracle Net to `discovery_cidr` (this VPC) themselves, so the rules survive their own `apply`. |

Targets in the import list when everything is on (12 hosts):

| Stack | Hosts | Access |
|---|---|---|
| fleet | 6 synthetic Linux roles | SSH `ec2-user` |
| Windows | `contoso-sql-01` (SQL 2022 Express) | WinRM `discovery` |
| sqlmod | SQL Server 2022 host (AL2023), Contoso Scoreboard (Windows/IIS), Project Nami (Ubuntu 22.04) | SSH `ec2-user` / WinRM `discovery` (secret `fbctf-sqlmod/app-winrm`) / SSH `ubuntu` |
| oramod | Oracle 21c XE host, Contoso Catalog (both AL2023) | SSH `ec2-user`, plus the Oracle module on `:1521` with `transform_ro` |

The discovery is **real** even though the fleet hosts are synthetic: real SSH,
real `ps`/`ss`/`dmidecode`, real 10-minute metric samples.

## Cost

`t3.xlarge` ≈ $0.17/hr + 6 × `t3.small` ≈ $0.12/hr + the Windows box ≈ **$0.30/hr**.
A 2-hour discovery run ≈ **$0.60**. Every host self-terminates after
`max_lifetime_minutes` (default 300; `0` disables).

## Run

`sqlmod` and `oramod` must already be applied (the data sources look up their
instances by tag).

```sh
cp environments/discovery-collector/terraform.tfvars.example environments/discovery-collector/terraform.tfvars
make apply ENV=discovery-collector       # ~4 min; the tool installs in user-data (~3 min more)
terraform -chdir=environments/discovery-collector output next_steps
```

Then follow `next_steps`: port-forward the UI, key the Linux hosts in the peered
stacks, add the SSH / WinRM / Oracle credentials + the import source, let it
collect, download the export, upload it to the assessment.

```sh
make destroy ENV=discovery-collector      # removes the peering + routes too
```

## Notes

- The SSH private key is placed in the collector's user-data (visible in
  instance metadata). Acceptable for a throwaway collector in the sandbox; the
  key only grants SSH to the throwaway fleet and, temporarily, the demo hosts.
- Configure two OS credentials in the UI with the same key: `ec2-user`
  (Amazon Linux) and `ubuntu` (Project Nami).
- The tool needs time to sample: metrics every 10 min, processes hourly,
  netstat every 15 s. A 1–2 h window is enough for a demo; the assessment will
  note the short window (that's honest). The app hosts hold one DB connection
  open so the app→DB edges are captured even during a short run.
