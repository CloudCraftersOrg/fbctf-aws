# 006 — Retire the fbctf live app

**Status:** accepted, 2026-09-01. Supersedes the "live app" role of [ADR 004](004-demo-scope-expansion.md).

## Context

`environments/demo` ran [facebookarchive/fbctf](https://github.com/facebookarchive/fbctf)
(Hack on HHVM 3.21, nginx, RDS MySQL, ElastiCache) as the demo's live application.
It never earned its keep for AWS Transform:

- **No code-modernization path.** Transform has no PHP/Hack transformation agent,
  so fbctf could only ever be the "cannot modernize, must rewrite" example.
- **MySQL-locked.** The app cannot move to SQL Server or Oracle without a full
  rewrite, so it could not participate in the database-modernization story.
- ~$5/day when up; a 2-tier ASG + ALB + NLB + RDS + ElastiCache to maintain.

Meanwhile `environments/sqlmod` grew a real workload: a Windows + IIS + .NET
Framework app (**Contoso Scoreboard**) and a PHP app (**Project Nami**), both on
one EC2 **SQL Server**. That estate exercises assessment/discovery, .NET
Framework → .NET 8, and SQL Server → Aurora *with live app data layers*.

## Decision

Retire fbctf. `terraform destroy` `environments/demo` (82 resources) and delete
the root. `discover_fbctf` in `environments/discovery-collector` is off.

The demo's live application is now the `environments/sqlmod` estate.

## Consequences

- These modules lose their only consumer and are now dead code (kept as
  reference, not wired to any root): `alb-external`, `cache`, `config`,
  `database`, `iam`, `nlb-internal`, `observability`, `security`,
  `service-tier`, `flow-log`, `vpc-endpoints`.
- `fbctf-aws-requirements.md` describes the retired app; it stays as history.
- `inventory/` still lists two real fbctf `i-*` servers — replace with the
  sqlmod hosts on the next inventory pass.
- The `fbctf-demo-tfstate` bucket keeps an empty `fbctf-demo/` state key.
