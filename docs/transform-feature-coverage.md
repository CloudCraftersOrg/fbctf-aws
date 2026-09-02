# AWS Transform feature coverage

What each part of this repo demonstrates and what it costs. Everything here is
the **legacy "before" state** — Transform produces the "after". Region:
**us-east-1** covers every capability below.

## The parts

| Part | What it is | Deployed? | Cost |
|---|---|---|---|
| `inventory/` | 14-server portfolio → `generate.py` → one assessment ZIP (+ `--vmware` for the VMware job); plus the committed real discovery-tool export | No — data | `$0` |
| `modernization/` | 4 code fixtures — .NET Framework / Java 8 / GnuCOBOL / T-SQL — + `atx-task.md` | No — source | `$0` (+ paid agents, below) |
| `environments/sqlmod` | SQL Server 2022 on EC2 + **Contoso Scoreboard** (.NET Framework 4.8 / IIS / Windows) + **Project Nami** (WordPress on SQL Server / PHP), 2-AZ VPC | On demand | ~$0.20/hr up, `$0` destroyed |
| `environments/oramod` | Oracle 21c XE on EC2 + **Contoso Catalog** (Java 8 / Spring Boot 2.7), 2-AZ VPC | On demand | ~$0.15/hr up, `$0` destroyed |
| `environments/discovery-collector` | the real AWS Transform discovery tool on an EC2 host + a 6-host Linux fleet + a Windows/SQL Express box; peers into sqlmod and oramod | On demand | ~$0.30/hr, self-terminating |
| `environments/artifacts` | persistent S3 bucket of vendored packages | Deployed, persists | ~$0 |

## Coverage matrix

| Transform capability | Demo path | Deploy | Cost |
|---|---|---|---|
| Assessment discovery (MPA import) | `inventory/generate.py` → upload `out/fbctf-assessment.zip` | no | `$0` |
| Discovery via the **real AWS Transform discovery tool** | `environments/discovery-collector` runs the Linux-installer tool; it SSH/WinRM-collects 12 hosts (6-host fleet + Windows/SQL Express + the 3 sqlmod hosts + the 2 oramod hosts) → `discovery_tool_export.zip`. The last export is committed at `inventory/discovery-tool-export/` and can be uploaded as-is | on demand, or `$0` with the committed export | ~$0.30/hr, self-terminating |
| Discovery of a live AWS account without the tool | **no AWS-native scan exists** — see [ADR 005](decisions/005-drop-the-estate.md). Upload the tool export or the MPA ZIP | — | — |
| Dependency map / move groups / wave planning | `network_connections.csv` **inside the same ZIP** as the servers file; the tool export carries the 3 real app→DB edges | no | `$0` |
| EC2 / EBS right-sizing | over-provisioned + idle rows + utilisation columns in `fleet.yaml` | no | `$0` |
| OS end-of-support | EOL OS strings (Ubuntu 16.04, Win 2012 R2, RHEL 7) in `fleet.yaml` | no | `$0` |
| TCO / business case | assessment scenario + baseline in chat → PDF / PPTX / XLSX | no | `$0` |
| Rehost / replatform / refactor / retire | process names in `connections.yaml` + chat steering | no | `$0` |
| .NET Framework → .NET 8 | `environments/sqlmod/app` (the deployed Web Forms app) or `modernization/dotnet-scoreboard` (MVC 5 + WCF fixture) → .NET code job | no | `$0` |
| Java 8 → 17 | `modernization/java-catalog` or `environments/oramod/app` → `atx AWS/java-version-upgrade` | no | **paid** — $0.035/agent-min (~$2.50) |
| Mainframe / COBOL → Java | `modernization/cobol-rollup` → S3 → mainframe job | no | `$0` |
| SQL Server → Aurora — full agentic | `environments/sqlmod` live SQL Server + the .NET 8 output of the .NET job → SQL Server modernization job | **yes** | sqlmod + Transform's DMS instance + Aurora |
| SQL Server → Aurora — schema conversion only | `modernization/sqlserver-schema/*.sql` → AWS SCT desktop, offline | no | `$0` |
| Oracle → Aurora PostgreSQL | `environments/oramod` live Oracle XE (`PRODUCT_SEQ` + trigger, PL/SQL package, view, `VIRTUAL` column) + the Java data layer | **yes** | oramod + Transform's DMS instance + Aurora |
| Transform Custom (`atx`) | `modernization/atx-task.md` custom definition | no | **paid** — $0.035/agent-min (~$1–3) |
| VMware migration — planning | `inventory/generate.py --vmware` → `out/fbctf-vmware-import.zip` → VMware migration job + a discovery account connector | no (S3 bucket) | ~`$0` |
| VMware migration — replication/cutover | **not demoable** — MGN needs running source VMs and a staging VPC | — | — |
| The "un-modernizable" story | **Project Nami** (PHP) in `environments/sqlmod` — Transform routes its SQL Server to Aurora but has no PHP code path; the runtime needs a rewrite or a container lift | **yes** | in sqlmod |

**Free:** migration assessments, discovery tool, .NET, mainframe, VMware agents.
**Paid:** Transform Custom and the AWS-managed language upgrades it runs (Java) —
$0.035/agent-minute of server-side work.

## Access

`AWSTransformAccess` already carries `transform:*` (the web app) **and**
`transform-custom:*` (the `atx` CLI, for Java 8→17 and Transform Custom) —
merged to `aws-access` main as commit `7d8af6b`. No further grant needed. The
`atx` CLI is installed on this machine.

The AWS Transform **web application** (assessment, .NET, mainframe, SQL Server,
Oracle, VMware jobs) requires **IAM Identity Center** access mode. That mode is
chosen when Transform is first enabled and **cannot be changed afterward**. This
account is enabled with IAM Identity Center, so every job works. If an account
were enabled IAM-only, the full agentic database jobs would be **impossible**
there — fall back to offline schema conversion (`$0`). The `atx` CLI (Java,
Custom) needs only ordinary credentials, no Identity Center.

## Run order

See [`demo-runbook.md`](demo-runbook.md).
