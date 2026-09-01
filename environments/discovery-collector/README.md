# discovery-collector — run the real AWS Transform discovery tool

`inventory/` gives Transform an assessment ZIP built from asserted data.
`inventory/discovery-export/` emulates the discovery-tool export format.
**This env runs the actual tool** — the Linux installer on one EC2 host — and
lets it **SSH into live servers** to collect genuine inventory, CPU/RAM/disk
metrics, running processes, and netstat dependencies, then export
`discovery_tool_export.zip` for the migration assessment.

## What it creates

| | |
|---|---|
| VPC `10.70.0.0/16` + public subnet | peered to the fbctf demo VPC when `discover_fbctf = true` |
| Collector | `t3.xlarge` (4 vCPU / 16 GB — the tool's minimum), Amazon Linux 2023; user-data installs `AWS-Transform-discovery-tool.sh` and stages the import CSV + SSH key |
| Fleet | 6 × `t3.small` — `catalog-svc-01` (Java 8), `finance-batch-01` (COBOL), `cache-01` (Redis), `mq-01` (RabbitMQ), `nfs-01` (NFS), `ci-01` (Jenkins) — real role processes + inter-node chatter for the dependency graph |
| Windows | 1 × `t3.small`, **Windows Server 2022 + SQL Server 2022 Express** (`enable_windows`, default on) — WinRM HTTPS + a `discovery` local admin, IIS (`w3wp`), SQL on 1433. Exercises the tool's WinRM path, **SQL Server module**, and Windows OS discovery. Creds in `terraform output -json windows_target`. |
| fbctf peering | VPC peering + routes + a `:22` ingress rule on the fbctf app/web SGs from the collector (removed on destroy) |

The Linux fleet uses the SSH credential; the Windows box needs a **WinRM
credential** added in the tool UI — `Set up access → Credentials → WinRM`,
username `discovery`, NTLM, the password from `terraform output`.

The discovery is **real** even though the fleet hosts are synthetic: real SSH,
real `ps`/`ss`/`dmidecode`, real 10-minute metric samples.

## Cost

`t3.xlarge` ≈ $0.17/hr + 6 × `t3.small` ≈ $0.12/hr ≈ **$0.30/hr**. A 2-hour
discovery run ≈ **$0.60**. Every host self-terminates after
`max_lifetime_minutes` (default 300).

## Run

```sh
cp environments/discovery-collector/terraform.tfvars.example environments/discovery-collector/terraform.tfvars
make apply ENV=discovery-collector       # ~4 min; the tool installs in user-data (~3 min more)
terraform -chdir=environments/discovery-collector output next_steps
```

Then follow `next_steps`: port-forward the UI, key the fbctf hosts, add the SSH
credentials + the import source, let it collect, download the export, upload it
to the assessment.

```sh
make destroy ENV=discovery-collector      # removes the fbctf SG rule + peering too
```

## Notes

- The SSH private key is placed in the collector's user-data (visible in
  instance metadata). Acceptable for a throwaway collector in the sandbox; the
  key only grants SSH to the throwaway fleet and, temporarily, the fbctf hosts.
- The fbctf hosts are Ubuntu 16.04 → SSH user `ubuntu`; the fleet is AL2023 →
  `ec2-user`. Configure both as OS credentials in the UI (same key).
- The tool needs time to sample: metrics every 10 min, processes hourly,
  netstat every 15 s. A 1–2 h window is enough for a demo; the assessment will
  note the short window (that's honest).
