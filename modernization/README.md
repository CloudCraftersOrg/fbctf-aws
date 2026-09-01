# Modernization fixtures — Transform code-transformation input

AWS Transform's assessment (see [`../inventory/`](../inventory)) recommends
*what* to modernize. These four fixtures are the *code* its transformation
agents actually rewrite. They are deliberately small but structurally real:
each one contains the specific constructs that force a non-trivial
transformation, so the agent produces a meaningful plan and pull request rather
than a one-line diff.

They are **source only** — nothing here is deployed, so nothing here costs
money. The optional runtime check (deploy the transformed output to Fargate +
Aurora) is described in
[`../docs/transform-feature-coverage.md`](../docs/transform-feature-coverage.md).

| Fixture | Stack | Transform capability | Built-in friction |
|---|---|---|---|
| [`dotnet-scoreboard/`](dotnet-scoreboard) | ASP.NET MVC 5, .NET Framework 4.8, EF6, a WCF service | **.NET Framework → cross-platform .NET** | `System.Drawing` + `System.Web` + `HttpContext.Current`, `packages.config`, `Web.config` transforms, `Global.asax`, WCF `.svc` |
| [`java-catalog/`](java-catalog) | Java 8, Spring Boot 2.3, Maven | **Java 8 → 17** | `javax.*` namespace, `WebSecurityConfigurerAdapter`, `Date`/`SimpleDateFormat`, JUnit 4, old dependency versions |
| [`cobol-rollup/`](cobol-rollup) | GnuCOBOL, fixed-width files, shell "JCL" | **Mainframe / COBOL modernization** | `COMP-3` packed decimal, `OCCURS`, `PERFORM ... THRU`, `GO TO`, indexed file I/O, copybooks |
| [`sqlserver-schema/`](sqlserver-schema) | T-SQL DDL | **SQL Server → Aurora schema conversion** | `MERGE`, `IDENTITY`, sequences, `TOP`, cursors, `GETDATE()`, computed columns, a trigger, a scalar UDF |

## Pointing Transform at a fixture

**Standard agents** (.NET, Java, mainframe): AWS Transform console → **Transform
code** → connect the repo → select the fixture directory as the project root →
choose the target (`.NET 8`, `Java 17`, or the mainframe target) → review the
generated transformation plan and PR.

**Schema conversion**: runs inside the migration assessment for
`contoso-sql-01`, or standalone via the AWS Schema Conversion Tool / DMS Schema
Conversion pointed at `sqlserver-schema/*.sql`.

**Transform Custom (`atx` CLI)**: see [`atx-task.md`](atx-task.md) for a job
that does something the stock agents do not — generating the target Terraform
for the modernized `dotnet-scoreboard`.
