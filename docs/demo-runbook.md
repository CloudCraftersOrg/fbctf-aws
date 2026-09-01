# AWS Transform demo runbook

End-to-end script for showing every AWS Transform capability. Region throughout:
**us-east-1**. Everything is web-app + chat except `atx` (a CLI).

Coverage and costs: [`transform-feature-coverage.md`](transform-feature-coverage.md).

---

## 0. Prerequisites (once)

| Need | Check |
|---|---|
| AWS Transform enabled in us-east-1 | Console → AWS Transform. "Get started" = not enabled; a **Web application URL** in Settings = enabled. Enable with **web application** capability + **IAM-only** user access (permanent). `AWSTransformAccess` covers this. |
| `atx` CLI (for Java + Custom) | `atx --version`. Installed on this machine. Grant `transform-custom:*` is on `aws-access` main (`7d8af6b`). |
| AWS SCT desktop (for offline schema conversion) | download from AWS; no account needed for offline mode. |
| Sign in | `aws sso login --sso-session diego-personal`, then open the Web application URL. |

Create one **workspace**; every job below lives in it.

---

## Layer A — Migration assessment (features 1–6)

Covers discovery, dependency mapping, move groups, wave planning, right-sizing,
OS end-of-support, TCO. **$0.**

1. `python3 inventory/generate.py` → `inventory/out/fbctf-assessment.zip`.
2. Workspace chat: `create a job` → **Assess workloads for migration readiness**.
3. First task **Discover on-premises data** → upload **`fbctf-assessment.zip`**
   (servers + connections + intent, one ZIP — the connections file is only read
   when zipped with the servers).
4. Expand **Inventory readiness summary**. Expect **14 servers**, an OS
   breakdown flagging Ubuntu 16.04 / Windows 2012 R2 / RHEL 7, and a dependency
   graph from the 18 edges.
5. Paste `inventory/ASSESSMENT_INTENT.md` into chat as the brief. Then walk:
   - `show the move groups and the proposed wave plan`
   - `right-size every server; call out the over-provisioned and idle ones`
   - `which servers are retire candidates?` (→ `ci-01`)
   - `which are replatform-to-managed candidates?` (→ cache/mq/nfs)
6. Scenario assumptions: target us-east-1, On-Demand, gp3. **Run.**
7. TCO: `compare as-is 24/7 vs rehost-right-sized vs modernize, with On-Demand /
   Savings Plan / RI pricing. Set a $500/server/month on-prem baseline for the
   contoso-* hosts.`
8. Generate the **PDF / PPTX / XLSX** deliverables (Artifacts view).

---

## Layer B — Code modernization (features 7, 8, 9, 10b, 11)

All from source — nothing is deployed.

### 7 · .NET Framework → .NET 8 — free

1. Chat: `create a job` → **Transform code** → **.NET**.
2. Connect the repo (or drag-drop a ZIP); project root
   **`modernization/dotnet-scoreboard`** (a real `net48` MVC 5 + EF6 + WCF +
   `System.Drawing` solution).
3. Target **.NET 8**. Review the assessment report → approve the transformation
   plan → review the PR on the new target branch.
4. **Keep this branch** — Layer C feature 10a consumes it.

### 8 · Java 8 → 17 — paid (~$2.50)

```sh
cd modernization/java-catalog        # Spring Boot 2.3 / Java 8 WAR, must build
atx                                  # then: "run AWS/java-version-upgrade on ./ targeting Java 17"
```
Review with `git diff` / `git log`. Covers `javax`→`jakarta`, Spring Boot 2→3,
JUnit 4→5, `WebSecurityConfigurerAdapter`.

### 9 · Mainframe / COBOL → Java — free

1. Upload `modernization/cobol-rollup/` (`ROLLUP.cbl` + copybooks + `RUNROLL.sh`
   + `scores.dat`) to the S3 bucket Transform provisions for the mainframe job.
2. Chat: `create a job` → mainframe modernization → objective:
   `analyze and refactor this COBOL batch to Java`.
3. Walk the HITL gates: code analysis → tech doc → business-logic extraction →
   domain decomposition → wave plan → COBOL→Java (+ optional Reforge pass) → IaC.

### 10b · SQL Server schema conversion — offline, free

1. AWS SCT desktop → new project → **offline** → add the DDL script files
   `modernization/sqlserver-schema/{01_tables,02_programmability,03_seed}.sql`.
2. Target **Aurora PostgreSQL**. Run the assessment.
3. Show the conversion report flagging as *manual*: `MERGE`, `IDENTITY` +
   `SCOPE_IDENTITY()`, `SEQUENCE`/`NEXT VALUE FOR`, the scalar UDF in a computed
   column, the `AFTER INSERT` trigger, the explicit cursor, `TOP … WITH TIES`.

### 11 · Transform Custom (`atx`) — paid (~$1–3)

Point a custom definition at the **.NET 8 branch from feature 7** to generate
target Terraform — see [`../modernization/atx-task.md`](../modernization/atx-task.md).

---

## Layer C — Live migrations (feature 10a, 12, the un-modernizable story)

### 10a · SQL Server → Aurora, full agentic

**Prerequisite:** Transform in **IAM Identity Center** access mode (not IAM-only).
Check Transform → settings. If permanently IAM-only, skip this — feature 10b
already covered schema conversion.

```sh
cp environments/sqlmod/terraform.tfvars.example environments/sqlmod/terraform.tfvars   # set transform_ro_password
make apply ENV=sqlmod                 # ~10 min
```

1. Chat: `create a job` → **SQL Server modernization**.
2. Source database: the `sql_server_address` output, port 1433, database
   `Scoreboard`, login `transform_ro`. DMS replication subnet group →
   `dms_subnet_ids` output.
3. Application repo: the **.NET 8 branch from feature 7**.
4. Walk: schema assessment → T-SQL → PL/pgSQL conversion → .NET data-layer
   rewrite (Npgsql) → connection-string updates → optional IaC + ECS deploy.
5. `make destroy ENV=sqlmod` — and delete the Transform-created DMS instance and
   Aurora target from the job.

### 12 · VMware migration — planning only

No VMware Cloud subscription needed (Transform migrates VMware→EC2 via MGN). No
running VMs = discovery/planning only, no replication/cutover.

1. `python3 inventory/generate.py --vmware` → a VMware-flavoured import file.
2. Console → add a **discovery account connector** (creates an S3 bucket in the
   account).
3. Chat: `create a job` → **Migrations (including VMware)** →
   **Import independently collected discovery data** → upload the file.
4. Walk: discovery → AI network/VPC design → application grouping → **wave plan**
   → migration runbook. Stop before replication.

### The un-modernizable story — fbctf

```sh
make apply                            # ~12 min + ~10 min boot; ENV defaults to demo
```

1. `alb_dns_name` output serves the Facebook CTF scoreboard (plain HTTP).
2. Run a Layer-A assessment of its 2 servers (or reuse the `i-*` rows already in
   the 14-server inventory).
3. Chat: `can AWS Transform modernize this application's code? It is PHP/Hack on
   HHVM 3.21.` → capture the answer: **no code path** — .NET / Java / mainframe
   only. Infra gets a Fargate + Aurora recommendation; the runtime needs a
   rewrite, flagged as a follow-on.
4. `make destroy` — the app runs an EOL OS, don't leave it up.

---

## Teardown checklist

| Item | Command |
|---|---|
| fbctf app | `make destroy` |
| sqlmod | `make destroy ENV=sqlmod` |
| Transform DMS instance / Aurora target | delete from the SQL Server job |
| VMware discovery connector | delete from the console |
| `environments/artifacts` | **leave it** — persists |
