# ADR 005 — Drop `environments/estate`

**Status:** Accepted (2026-09-01). Supersedes the `environments/estate` part of
[ADR 004](004-demo-scope-expansion.md).

## Context

ADR 004 added `environments/estate` — 12 EC2 hosts deployed as "the legacy estate
Transform discovers." It was built and applied (12 running hosts, ~$14/day).

Researching Transform's actual assessment inputs showed the premise was wrong:

- The migration assessment ingests **only uploaded inventory files** (Transform
  discovery-tool export, MPA import, RVTools, CMDB, Migration Evaluator, the
  Excel data template) or a free-text chat description.
- There is **no AWS-native "scan my account" mode**. "Agentless" in AWS's
  vocabulary means the VMware vCenter OVA collector, not an AWS API crawl.
- AWS Application Discovery Service is closed to new customers; AWS points you to
  Transform.
- So the running estate was **invisible** to Transform. And because it was
  deployed at small instance sizes to control cost, a live agent (if one had been
  possible) would have reported "already right-sized" — erasing the finding.

## Decision

Destroy the deployment and remove `environments/estate/` and
`modules/estate-host/` from the repo.

- Assessment discovery is covered by `inventory/` (the MPA import ZIP).
- "Discovered for real" is covered by `inventory/discovery-export/` — the
  read-only-API + CloudWatch + SSM method that turns the live fbctf account into
  a discovery-tool-format export.
- The one Transform capability that genuinely needs live infra — the full agentic
  SQL Server → Aurora job — gets a small purpose-built `environments/sqlmod`
  (RDS SQL Server Express in a 2-AZ VPC), not a 12-host fleet.

## Consequences

- ~$14/day saved.
- The live demo footprint is `environments/demo` (fbctf) + `environments/sqlmod`,
  both on-demand, plus the persistent artifacts bucket.
- Nothing about Transform feature coverage is lost — see
  `transform-feature-coverage.md`.
