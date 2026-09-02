# ADR 004 — Expand the demo from one app to an estate, without adding spend

**Status:** Accepted (2026-09-01). **Point 3 (`environments/estate`) superseded by
[ADR 005](005-drop-the-estate.md)** — Transform cannot discover a running AWS
account, so the estate was destroyed and removed. Points 1 (`inventory/`) and 2
(`modernization/`) stand.

## Context

The repo deployed one workload (fbctf) as the AWS Transform "before" state. It
exercises the assessment path — inventory, right-sizing, dependency mapping,
TCO, OS end-of-support — but only for two Linux servers, and **none** of
Transform's code-modernization features:

- Hack/HHVM is not a language any Transform agent supports.
- The app's MySQL returned "no compatible routing target" — only SQL Server
  routes to Aurora in the assessment.
- No .NET, no Java, no COBOL, no schema conversion, no Transform Custom.

To demo the whole product we need more OS variety, a richer dependency graph,
a SQL Server database, and real code in the languages the agents transform.

## Decision

Add three things, structured so cost stays near zero:

1. **`inventory/`** — a 14-server estate expressed as **data**, not
   infrastructure. `generate.py` turns `fleet.yaml` + `connections.yaml` into
   the MPA import CSVs. Never deployed. This is the primary assessment input;
   the live app becomes one workload within a larger picture.

2. **`modernization/`** — four code fixtures (.NET Framework 4.8, Java 8,
   GnuCOBOL, T-SQL). Source only. Each contains the specific constructs that
   force a non-trivial transformation, so the agents produce a real plan and PR.

3. **`environments/estate/`** — 12 of the 14 hosts deployed for real (the fbctf
   pair stays in `environments/demo`). Small instance sizes, SQL Server Express
   (licence-free), one destroyable root, every host self-terminating via
   `shutdown +N` + terminate-on-shutdown. For pointing Transform at a live
   account; the CSV import still drives right-sizing and TCO. An earlier
   iteration had a separate 4-node `discovery-fleet` — dropped, the estate with
   `enable_discovery_agent` covers it and one throwaway env is enough.

The live `environments/demo` app and `environments/artifacts` are unchanged.

## Consequences

- Full Transform feature coverage (except VMware, which needs VMware Cloud on
  AWS) for **under $20 total** to run once — see
  `transform-feature-coverage.md`.
- The MPA CSV column names are pinned by `generate.py` and were verified against
  a live upload on 2026-08-27; the `i-*` rows must stay byte-identical to that
  upload.
- `environments/estate` uses only IAM/VPC/EC2/Route53 the `AWSTransformAccess`
  set already grants; role and instance-profile names carry the `fbctf-` prefix
  the set scopes to.
- Deploying the estate at `fleet.yaml`'s deliberately-oversized specs would cost
  $200+/day. It deploys at small sizes instead; a live discovery agent then
  reports the true small specs, so right-sizing and TCO findings come from the
  CSV import, not the estate.
- Modernizing the transformed output (Fargate + Aurora) is out of scope — it
  needs `ecs:*` the set does not grant, and it is Transform's job, not the
  "before" state's.
- `atx` (Transform Custom) still needs a `transform-custom:*` grant that is not
  in place; `modernization/atx-task.md` carries the one-statement PR.
