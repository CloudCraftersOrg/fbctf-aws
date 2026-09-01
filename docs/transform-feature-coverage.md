# AWS Transform feature coverage

What each part of this repo demonstrates, and what it costs to run.

## The three parts

| Part | What it is | Deployed? | Cost |
|---|---|---|---|
| `environments/demo` | The live fbctf app — one real legacy workload (Hack/HHVM, nginx, MySQL 8, memcached on Ubuntu 16.04 EOL) | Yes, on demand | ~$5/day while up, `$0` destroyed |
| `inventory/` | A 14-server simulated estate as CSV data for the MPA assessment import | No | `$0` |
| `modernization/` | Four code fixtures — .NET Framework, Java 8, COBOL, T-SQL | No | `$0` |
| `environments/discovery-fleet` | Throwaway spot fleet running the live discovery agent | On demand | ~$0.10/run, self-terminating |

## Coverage matrix

| Transform capability | Demonstrated by | Cost |
|---|---|---|
| Discovery — MPA import | `inventory/` → `generate.py` → two CSVs | `$0` |
| Discovery — live agent | `environments/discovery-fleet` | ~$0.10 |
| Dependency mapping, move groups, wave planning | `inventory/connections.yaml` (18 edges); agent netstat capture | `$0` |
| EC2 / EBS right-sizing | over-provisioned + idle hosts in `fleet.yaml` (`contoso-web-01`, `sql-rpt-01`, `nfs-01`, `sql-01`) | `$0` |
| OS end-of-support findings | Ubuntu 16.04, Win 2012 R2, RHEL 7 in `fleet.yaml`; the live app is a real one | `$0` |
| Rehost / replatform / refactor / retire dispositions | one of each is the right call for some host (`ci-01` retire, `cache-01` replatform, web tier refactor) | `$0` |
| TCO / business case | Transform computes it from the imported inventory + `Environment Type = Production` | `$0` |
| .NET Framework → cross-platform .NET | `modernization/dotnet-scoreboard` | `$0` |
| Java 8 → 17 | `modernization/java-catalog` | `$0` |
| Mainframe / COBOL modernization | `modernization/cobol-rollup` | `$0` |
| SQL Server → Aurora + schema conversion | `modernization/sqlserver-schema` + `contoso-sql-01` in the inventory | `$0` |
| Self-managed → managed service | `cache-01` → ElastiCache, `mq-01` → Amazon MQ, `nfs-01` → EFS (recommended from process names in the connection data) | `$0` |
| Transform Custom (`atx`) | `modernization/atx-task.md` — generate the target Terraform | ~$1–3 per job |
| Runtime validation of the transformed output | *optional* — deploy the ported app to Fargate + Aurora Serverless v2, one afternoon | ~$2–5, needs an `aws-access` PR for `ecs:*` |
| VMware migration | **not covered** — requires VMware Cloud on AWS | — |

**Exercise every covered feature once: well under $10**, most of it the live app
if you run it a full day plus one `atx` job.

## Order to run a full demo

1. `python3 inventory/generate.py` → upload both CSVs to a new Transform
   assessment. Walk the inventory, dependencies, right-sizing, TCO, wave plan.
2. *(optional)* `make apply ENV=discovery-fleet` → show the same discovery
   happening live via the agent. `make destroy ENV=discovery-fleet`.
3. `make apply` (root env) → show the live "before" app, then the assessment's
   view of its two servers and the "code Transform cannot modernize" call-out
   (Hack/HHVM). `make destroy`.
4. Point the standard code agents at `modernization/dotnet-scoreboard`,
   `java-catalog`, `cobol-rollup`; run schema conversion on `sqlserver-schema`.
5. Run the `atx` custom job from `modernization/atx-task.md` for the target
   Terraform.
