# sqlmod — live SQL Server for the Aurora modernization job

Every other Transform feature in this repo needs no infrastructure. The **full
agentic SQL Server → Aurora** job is the exception: it reads a **live** database
through a DMS replication instance it creates in your VPC, converts the T-SQL
stored procedures to PL/pgSQL, and rewrites the .NET data-access layer.

This root gives it the smallest thing that satisfies its prerequisites.

## What it creates

| | |
|---|---|
| VPC (`modules/network`) | `10.40.0.0/16`, **2-AZ** database subnets (the DMS replication subnet group needs ≥2 AZs) |
| RDS **SQL Server Express** | `fbctf-sqlmod`, `db.t3.small`, `sqlserver-ex` 2019, single-AZ, private, RDS-managed master secret |
| S3 bucket `fbctf-sqlmod-schema-*` | staging for the three `modernization/sqlserver-schema/*.sql` files |
| Schema loader | throwaway `t3.micro` — installs `sqlcmd`, runs the DDL, creates the `transform_ro` login (`VIEW DEFINITION` + `VIEW DATABASE STATE`), then idles |

Security group opens `1433` to the whole VPC CIDR, so Transform's DMS instance
reaches it wherever Transform places it.

## Prerequisite — Transform access mode

The SQL Server modernization job requires **IAM Identity Center** access mode for
AWS Transform. This account may have enabled Transform with **IAM-only** access
(a permanent choice). **Check the Transform console → settings first.** If it is
permanently IAM-only, this job is blocked — use offline schema conversion
instead (AWS SCT desktop on `modernization/sqlserver-schema/*.sql`, `$0`) and
skip this env.

## Run

```sh
cp environments/sqlmod/terraform.tfvars.example environments/sqlmod/terraform.tfvars
# edit transform_ro_password
make apply ENV=sqlmod                 # ~10 min (RDS creation dominates)
```

Then in the Transform SQL Server job, use the `sql_server_address` output, the
`transform_ro` login, database `Scoreboard`, and point the DMS subnet group at
`dms_subnet_ids`. Feed it the **.NET 8 output of the .NET modernization job**
(dotnet-scoreboard upgraded) as the application repo.

```sh
make destroy ENV=sqlmod               # after the demo — RDS + DMS are not free
```

## Cost

RDS `db.t3.small` SQL Server Express (license-included) ≈ $5–6/day + ~$0.25/day
for the loader + whatever Transform's DMS instance and the Aurora target cost
while running. `terraform destroy` removes everything this root owns; delete the
Transform-created DMS instance and Aurora target from the Transform job.
