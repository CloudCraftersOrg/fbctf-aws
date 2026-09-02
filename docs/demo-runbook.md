# AWS Transform demo runbook — run every feature, in order

A single linear pass through every Transform capability against the deployed
stack. Region: **us-east-1**. Profile: `personal-transform`. Transform is enabled
with **IAM Identity Center**, so every feature is available.

Feature coverage + costs: [`transform-feature-coverage.md`](transform-feature-coverage.md).

## The stack this assumes is deployed

| | |
|---|---|
| `environments/sqlmod` | SQL Server 2022 on EC2 + **Contoso Scoreboard** (.NET Framework 4.8 / IIS) + **Project Nami** (WordPress on SQL Server). `terraform -chdir=environments/sqlmod output` gives `sql_server_address`, `database_name` (`Scoreboard`), `transform_login` (`transform_ro`, password in `environments/sqlmod/terraform.tfvars`), `vpc_id`, `dms_subnet_ids`, `app_url`, `wordpress_url` |
| `environments/oramod` | Oracle 21c XE on EC2 + **Contoso Catalog** (Java 8 / Spring Boot 2.7). Outputs: `oracle_address` (`:1521`, PDB `XEPDB1`), `transform_ro_user`, `app_secret_arn` (holds the `transform_ro` password), `vpc_id`, `dms_subnet_ids`, `app_url` |
| `environments/discovery-collector` | optional — the real discovery tool; only for Phase 1 step 9 |
| Source bucket | `s3://fbctf-transform-src-337058058699-use1/` — holds `contoso-scoreboard-src.zip` (from `environments/sqlmod/app`), `dotnet-scoreboard-src.zip`, `java-catalog-src.zip`, `cobol-rollup-src.zip` |
| Assessment inputs | `inventory/out/fbctf-assessment.zip`, `inventory/out/fbctf-vmware-import.zip` (run `python3 inventory/generate.py --vmware` to refresh) and the committed `inventory/discovery_tool_export.zip` |
| `atx` CLI | v3.12.0, `AWS/java-version-upgrade` in the registry; JDK 17 + Maven on the machine |

## Three live apps, on purpose

| App | Stack | Role in the demo |
|---|---|---|
| **Contoso Scoreboard** | ASP.NET Web Forms / .NET Framework 4.8 / IIS → SQL Server | .NET → .NET 8 job, then the SQL Server → Aurora job rewrites its data layer |
| **Project Nami** | WordPress on SQL Server / PHP | the "un-modernizable" runtime: the database routes to Aurora, the PHP does not |
| **Contoso Catalog** | Java 8 / Spring Boot 2.7 → Oracle 21c XE | Java 8 → 17 via `atx`, then Oracle → Aurora PostgreSQL |

The `modernization/` fixtures are the undeployed, richer variants of the same
code (MVC 5 + WCF, Spring Boot 2.3, COBOL, T-SQL) for the agents that do not
need a live host.

---

## Phase 0 — setup (~10 min)

1. `aws sso login --sso-session diego-personal`.
2. Console (account 337058058699) → **AWS Transform** (us-east-1) → open the **Web application URL**.
3. **Workspaces** → **Create workspace** → open it.
4. Confirm the CLI: `AWS_PROFILE=personal-transform atx custom def list` — lists the AWS-managed transformations.
5. Deploy the stack (~15 min, both in parallel):
   ```sh
   make apply ENV=sqlmod
   make apply ENV=oramod
   ```

---

## Phase 1 — Migration assessment · features 1–6 + the "un-modernizable" close · **$0**

1. Workspace **Chat**: `create a job` → choose **Migration assessment**.
2. Job Plan → **Discover on-premises data**. When the **Collaboration pane** prompts for data, upload **`inventory/out/fbctf-assessment.zip`**.
   *If the ZIP is rejected: it also contains `ASSESSMENT_INTENT.md`; re-zip with just the two CSVs (`cd inventory/out && zip fbctf-assessment.zip mpa_servers.csv network_connections.csv`) and retry. The connections file is only read because it's zipped with the servers file.*
3. Paste the contents of **`inventory/ASSESSMENT_INTENT.md`** into chat.
4. Expand **Inventory readiness summary**: 14 servers; OS end-of-support breakdown (Ubuntu 16.04 ×3, Windows Server 2012 R2, RHEL 7); dependency graph from the 18 edges. Adjust with **Manage inventory scope** if wanted.
5. Chat, one prompt at a time:
   - `show the move groups and the proposed wave plan`
   - `right-size every server; call out the over-provisioned and idle ones`
   - `which servers are retire candidates?` → `ci-01`
   - `which should replatform to a managed service?` → `cache-01`→ElastiCache, `mq-01`→Amazon MQ, `nfs-01`→EFS
6. Set scenario assumptions: target **us-east-1**, **On-Demand**, EBS **gp3** → **Run**.
7. TCO in chat: `compare as-is 24/7 vs rehost-right-sized vs modernize, with On-Demand / 1-yr Savings Plan / RI pricing, using a $500/server/month on-prem baseline for the contoso-* hosts`.
8. **Artifacts** → generate the **PDF**, **PPTX**, and **XLSX**.
9. **The real discovery-tool angle** — two options:
   - **`$0`:** upload the committed **`inventory/discovery_tool_export.zip`** as a second data source. It is a genuine export from the tool: 12 hosts, Windows + Linux, the SQL Server and Oracle modules, and the three app→DB edges (see `inventory/discovery-tool-export/README.md`).
   - **Live (~$0.60):** run the tool yourself:
     ```sh
     cp environments/discovery-collector/terraform.tfvars.example environments/discovery-collector/terraform.tfvars
     make apply ENV=discovery-collector
     terraform -chdir=environments/discovery-collector output next_steps
     ```
     Follow `next_steps`: SSM-port-forward the tool UI (`:5000`), key the Linux hosts, add the SSH / WinRM / Oracle credentials + the `import.csv` source, let it collect 1–2 h, then **Discovered inventory → Download inventory → `discovery_tool_export.zip`** and upload that. `make destroy ENV=discovery-collector` after.
10. **The close:** `Can AWS Transform modernize the code of the WordPress application on the SQL Server? It is PHP.` → capture the answer: **no supported code path** (only .NET, Java, mainframe/COBOL). Its SQL Server routes to Aurora; the PHP runtime is a container lift or a rewrite, flagged as a follow-on.

---

## Phase 2 — .NET Framework → .NET 8 · feature 7 · **$0** · **run before Phase 4**

1. Package the deployed app (see `environments/sqlmod/app/README.md`) → `s3://fbctf-transform-src-337058058699-use1/contoso-scoreboard-src.zip`. *(The richer undeployed fixture, `dotnet-scoreboard-src.zip`, works the same way.)*
2. Chat: `create a job` → **.NET modernization**.
3. **Get resources to be transformed** → **Connect a source code repository** → **Amazon S3** → the zip (one top-level folder containing `ContosoScoreboard.sln`).
4. Review discovery → the **transformation plan** → approve. Web Forms has no .NET Core successor, so expect the plan to call out a Razor Pages / Blazor port alongside `System.Data.SqlClient` → `Microsoft.Data.SqlClient` and `web.config` → `appsettings.json`.
5. Output: `transform-output/transformed-code.zip` + `diff.txt` in the bucket.
6. **Keep it for Phase 4:** download and extract; re-zip with one top-level folder as `contoso-scoreboard-net8-src.zip`; `aws s3 cp` it to the source bucket.

---

## Phase 3 — the independent code agents · features 8, 9, 10b, 11

Run in any order. 8 and 11 are the paid ones (`atx`, $0.035/agent-minute, `--limit` caps the spend).

### 8 · Java 8 → 17 · `atx` · ~$2.50

Either `modernization/java-catalog` (Spring Boot 2.3, undeployed) or
`environments/oramod/app` (Spring Boot 2.7, the deployed Contoso Catalog).

```sh
export JAVA_HOME=$(brew --prefix openjdk@17); export PATH="$JAVA_HOME/bin:$PATH"
rm -rf /tmp/java-catalog && cp -r modernization/java-catalog /tmp/java-catalog
cd /tmp/java-catalog && git init -q && git add -A && git -c user.email=d@l -c user.name=d commit -qm init

AWS_PROFILE=personal-transform AWS_REGION=us-east-1 \
  atx custom def exec -n AWS/java-version-upgrade -p . -c "mvn clean install" -x -t --limit 45
```
`mvn clean install` on the fixture passes today (verified). Review the result:
`git log --author="ATX Bot"` then `git diff <first-commit>`. Covers JDK 8→17,
`javax`→`jakarta`, Spring Boot 2→3, JUnit 4→5, `WebSecurityConfigurerAdapter`.
*(Alternative: `AWS/spring-boot-version-upgrade`.)* `atx` commits in place — it
does **not** push or open a PR.

### 9 · Mainframe / COBOL → Java · web job · $0

1. Chat: `create a job` → **Mainframe modernization**.
2. Source → **Amazon S3** → `s3://fbctf-transform-src-337058058699-use1/cobol-rollup-src.zip`.
3. Objective: `analyze and refactor this COBOL batch to Java`.
4. Walk the human-in-the-loop gates: code analysis → technical documentation → business-logic extraction → domain decomposition → wave plan → COBOL→Java (+ optional Reforge pass) → target IaC.
   The fixture: `ROLLUP.cbl` (`COMP-3`, `OCCURS`, `SEARCH`, `PERFORM … THRU`, `GO TO`), 2 copybooks, a shell "JCL", fixed-width `scores.dat`.

### 10b · SQL Server schema conversion · offline AWS SCT · $0

1. Download **AWS SCT** desktop. **New project** → do **not** connect a source; add **script files**.
2. Add `modernization/sqlserver-schema/{01_tables,02_programmability,03_seed}.sql`. Target: **Aurora PostgreSQL**. Run the assessment.
3. Show the conversion report flagging as *manual*: `MERGE`, `IDENTITY` + `SCOPE_IDENTITY()`, `SEQUENCE`/`NEXT VALUE FOR`, the scalar UDF inside a computed column, the `AFTER INSERT` trigger, the explicit `CURSOR`, `TOP … WITH TIES`, `usp_RecalculateRanks WITH EXECUTE AS OWNER`.

### 11 · Transform Custom (`atx`) · ~$1–3

Generate the target Terraform for the modernized .NET app — a job the stock agents don't do.

```sh
cp -r <Phase 2 extracted .NET 8 output> /tmp/dotnet8
cd /tmp/dotnet8 && git init -q && git add -A && git -c user.email=d@l -c user.name=d commit -qm init

AWS_PROFILE=personal-transform AWS_REGION=us-east-1 atx        # interactive
# > "Create a transformation definition that reads a modernized .NET project and
# >  emits a Terraform module for its target: ECS Fargate (2 tasks/2 AZs, ARM64),
# >  Aurora PostgreSQL Serverless v2, ALB + ACM + WAF, Secrets Manager, all names
# >  fbctf-after-*. Reference: <repo>/modernization/atx-task.md"
# > (test, iterate, then:)
atx custom def save-draft -n fbctf-after-terraform --description "target IaC for the modernized scoreboard" --sd <definition-dir>

atx custom def exec -n fbctf-after-terraform -p /tmp/dotnet8 -x -t --limit 30
```
Review with `git diff`. Output is in-place git commits; no PR.

---

## Phase 4 — SQL Server → Aurora, full agentic · feature 10a · needs Phase 2 + `sqlmod`

1. Chat: `create a job` → **SQL Server modernization**.
2. **Configure Database Connector** → New Connection, from `terraform -chdir=environments/sqlmod output`:
   | | |
   |---|---|
   | Endpoint | `sql_server_address` (private IP) |
   | Port | `1433` |
   | Database | `Scoreboard` |
   | Login | `transform_ro` |
   | Password | `transform_ro_password` from `environments/sqlmod/terraform.tfvars` |
   → **Test connectivity** (1433 is open to the whole VPC CIDR, so the DMS instance reaches it wherever Transform places it).
3. **Connect source code repository** → **Amazon S3** → `contoso-scoreboard-net8-src.zip` (from Phase 2).
4. **Set up Landing Zone** → Aurora PostgreSQL **Serverless v2**; `vpc_id`; the two `dms_subnet_ids`.
5. Walk: **Assessment** → **Wave planning** (approve) → **Schema conversion** (approve) → **Data migration** → choose **Synthetic Data Generation** or the live `Scoreboard` data → **Code migration** (approve — `SqlClient` → Npgsql, T-SQL → PL/pgSQL, connection strings) → **Validation review** → **Deployment approval** (CloudFormation/CDK → ECS).
6. Bonus: point Transform at the live **Contoso Scoreboard** (`app_url`) and **Project Nami** (`wordpress_url`) to show the "before" while the job runs.

---

## Phase 4b — Oracle → Aurora PostgreSQL · needs `oramod`

1. Chat: `create a job` → the **Oracle** database modernization job type.
2. **Database Connector**, from `terraform -chdir=environments/oramod output`:
   | | |
   |---|---|
   | Endpoint | `oracle_address` |
   | Port | `1521` |
   | Service / PDB | `XEPDB1` |
   | Login | `transform_ro` |
   | Password | `transform_ro` field of the secret at `app_secret_arn` |
3. **Source code** → the Java 17 output of Phase 3 step 8 run on `environments/oramod/app` (or the Java 8 source as-is).
4. **Landing Zone** → Aurora PostgreSQL Serverless v2; oramod `vpc_id` + `dms_subnet_ids`.
5. Walk the same gates. Expect `PRODUCT_SEQ` + `trg_products_bi` → identity, `catalog_pkg` → PL/pgSQL, `VW_CATALOG_SUMMARY`, the `VIRTUAL` column, `FROM dual`, and the JPA `@SequenceGenerator` + native `@Query` rewrites.

---

## Phase 5 — VMware migration planning · feature 12 · ~$0

1. Console → **Connectors** → add a **discovery account connector** (account 337058058699, us-east-1) → **copy the verification link** → approve it (creates an S3 bucket for discovery data). *If approval needs an AWS admin, ask @santiacmaestre.*
2. Chat: `create a job` → **Migrations (including VMware)** → job sub-type **Discovery and migration planning** (steps: Perform discovery → Build migration plan — **no** target-account connector, no replication).
3. **Perform discovery** → upload **`inventory/out/fbctf-vmware-import.zip`** → **Inventory readiness summary** (14 servers, `Hypervisor = VMware ESXi 7.0`, ESXi host / cluster / datastore fields).
4. **Build migration plan** → AI network / VPC design → application grouping → **wave plan** → migration runbook. **Stop here** — cutover needs running source VMs.
5. Delete the discovery connector when done.

---

## Phase 6 — teardown

```sh
make destroy ENV=discovery-collector   # if it was applied in Phase 1
make destroy ENV=sqlmod
make destroy ENV=oramod
aws s3 rb s3://fbctf-transform-src-337058058699-use1 --force
```

Also delete: the Transform-created DMS / Aurora / ECS resources from the SQL
Server and Oracle jobs; the VMware discovery connector. **Keep
`environments/artifacts`** (persistent).

---

## What "done" looks like

| Phase | Result |
|---|---|
| 1 | 14-server inventory readiness; a wave plan; a TCO scenario; PDF + PPTX + XLSX in Artifacts; the real tool export ingested; chat states PHP has no code path |
| 2 | `transformed-code.zip` — a .NET 8 solution |
| 3 | Java: `ATX Bot` commits + `mvn clean install` passes. COBOL: a COBOL→Java plan + wave plan. 10b: SCT report with the manual-conversion list. 11: a custom def in the registry + commits generating Terraform |
| 4 | connectivity test passes; PL/pgSQL schema on Aurora; a branch with the Npgsql-rewritten data layer |
| 4b | Oracle connectivity passes; `catalog_pkg` as PL/pgSQL; the JPA layer rewritten |
| 5 | VMware inventory readiness (14 servers, ESXi); a wave plan + network design + runbook |
| 6 | `terraform destroy` clean on sqlmod, oramod and the collector; source bucket gone; no orphan DMS/Aurora/ECS |
