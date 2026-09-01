# AWS Transform feature coverage

What each part of this repo demonstrates and what it costs. Everything here is
the **legacy "before" state** — Transform produces the "after". Region:
**us-east-1** covers every capability below.

## The parts

| Part | What it is | Deployed? | Cost |
|---|---|---|---|
| `inventory/` | 14-server portfolio → `generate.py` → one assessment ZIP | No — data | `$0` |
| `modernization/` | 4 code fixtures — .NET Framework / Java 8 / GnuCOBOL / T-SQL — + `atx-task.md` | No — source | `$0` (+ paid agents, below) |
| `environments/demo` | the real fbctf app (nginx + HHVM 3.21 + RDS MySQL + memcached on EOL Ubuntu 16.04) | On demand | ~$5/day up, `$0` destroyed |
| `environments/sqlmod` | RDS SQL Server Express in a 2-AZ VPC, for the full agentic SQL Server → Aurora job | On demand | RDS SQL Express + Transform's DMS instance + Aurora while running |
| `environments/artifacts` | persistent S3 bucket of vendored fbctf packages | Deployed, persists | ~$0 |

## Coverage matrix

| Transform capability | Demo path | Deploy | Cost |
|---|---|---|---|
| Assessment discovery (MPA import) | `inventory/generate.py` → upload `out/fbctf-assessment.zip` | no | `$0` |
| Discovery of a live AWS account | **no AWS-native scan exists** — read the account with read-only APIs + CloudWatch + SSM and format as a discovery-tool export (`inventory/discovery-export/`), then upload | no | `$0` |
| Dependency map / move groups / wave planning | `network_connections.csv` **inside the same ZIP** as the servers file | no | `$0` |
| EC2 / EBS right-sizing | over-provisioned + idle rows + utilisation columns in `fleet.yaml` | no | `$0` |
| OS end-of-support | EOL OS strings (Ubuntu 16.04, Win 2012 R2, RHEL 7) in `fleet.yaml` | no | `$0` |
| TCO / business case | assessment scenario + baseline in chat → PDF / PPTX / XLSX | no | `$0` |
| Rehost / replatform / refactor / retire | process names in `connections.yaml` + chat steering | no | `$0` |
| .NET Framework → .NET 8 | `modernization/dotnet-scoreboard` → .NET code job | no | `$0` |
| Java 8 → 17 | `modernization/java-catalog` → `atx AWS/java-version-upgrade` | no | **paid** — $0.035/agent-min (~$2.50); needs the `transform-custom:*` grant |
| Mainframe / COBOL → Java | `modernization/cobol-rollup` → S3 → mainframe job | no | `$0` |
| SQL Server → Aurora — full agentic | `environments/sqlmod` live SQL + the .NET 8 output of the .NET job → SQL Server modernization job | **yes** | RDS SQL Express + DMS instance + Aurora |
| SQL Server → Aurora — schema conversion only | `modernization/sqlserver-schema/*.sql` → AWS SCT desktop, offline | no | `$0` |
| Transform Custom (`atx`) | `modernization/atx-task.md` custom definition | no | **paid** — $0.035/agent-min (~$1–3); needs the `transform-custom:*` grant |
| VMware migration — planning | `inventory/vmware/` VMware-flavoured export → VMware migration job + a discovery account connector | no (S3 bucket) | ~`$0` |
| VMware migration — replication/cutover | **not demoable** — MGN needs running source VMs and a staging VPC | — | — |
| The "un-modernizable" story | `environments/demo` — assess fbctf; Transform recommends Fargate/Aurora for the infra but flags **Hack/HHVM** as no code path | **yes** | ~$5/day |

**Free:** migration assessments, discovery tool, .NET, mainframe, VMware agents.
**Paid:** Transform Custom and the AWS-managed language upgrades it runs (Java) —
$0.035/agent-minute of server-side work.

## Grants still needed

`transform-custom:*` on `AWSTransformAccess` — drafted as an `aws-access` PR.
Unblocks Java 8→17 and Transform Custom. Without it, .NET / COBOL / assessment /
schema conversion are still fully covered.

## Run order

See [`demo-runbook.md`](demo-runbook.md).
