# Simulated source estate — Transform assessment input

The live apps (`environments/sqlmod`, `environments/oramod`) are a handful of
hosts. A migration assessment needs an *estate*: enough servers, operating systems and dependencies that
right-sizing, move groups, wave planning and TCO have something to chew on, and
enough variety that every assessment finding shows up at least once.

This directory is that estate, expressed as **data, not infrastructure** — it
costs nothing and is never deployed. `generate.py` turns it into a single ZIP
that AWS Transform's migration assessment imports.

## Files

| File | Purpose |
|---|---|
| `fleet.yaml` | 14 servers. The two `i-*` hosts are the retired fbctf pair (kept because their rows were validated against a live upload — see [ADR 006](../docs/decisions/006-retire-fbctf.md)); the rest are synthetic. Each carries a `signal:` line naming the finding it exercises. |
| `connections.yaml` | Server-to-server dependency edges with process names. Every synthetic host has at least one edge, so nothing lands in a trivial one-host wave. |
| `ASSESSMENT_INTENT.md` | The modernization brief — pasted into the assessment chat. |
| `generate.py` | Emits `out/fbctf-assessment.zip` (+ the loose CSVs for inspection). `--check` validates without writing. |
| `requirements.txt` | `PyYAML` — the only dependency. |

## Generate the import

```sh
python3 -m pip install -r inventory/requirements.txt
python3 inventory/generate.py
# -> inventory/out/fbctf-assessment.zip  (mpa_servers.csv + network_connections.csv + ASSESSMENT_INTENT.md)
```

`out/` is gitignored — regenerate it, don't commit it.

## Feed it to Transform

1. AWS Transform (us-east-1) → workspace → chat "assess workloads for migration
   readiness".
2. Upload **`fbctf-assessment.zip`**. The connections file is only processed
   when it is zipped together with the servers file, which is why `generate.py`
   produces one ZIP.
3. Paste `ASSESSMENT_INTENT.md` into the chat as the brief.

Column names and order in the CSVs are fixed by the MPA template and were
verified against a live upload on 2026-08-27. `generate.py` will not let you
reorder them.

## What each server is here to trigger

| Finding | Hosts |
|---|---|
| OS end-of-support | `i-*` (Ubuntu 16.04), `contoso-worker-01` (Win 2012 R2), `catalog-svc-01` (RHEL 7), `mq-01` (Ubuntu 16.04) |
| EC2 over-provisioned → right-size | `contoso-web-01` (32 GB @ 14 % avg), `contoso-sql-rpt-01`, `cache-01` |
| EBS over-provisioned → right-size | `contoso-sql-01` (2 TB @ 18 %), `nfs-01` (4 TB @ 8 %) |
| Retire candidate | `ci-01` (3 % average CPU, idle off-hours) |
| No HA / single node | `contoso-web-01`, `contoso-sql-01` |
| Spiky / schedule-based sizing | `finance-batch-01` (peak 92 / avg 8) |
| Move-group cohesion | the `contoso-app-01`/`-02` + `sql-01` + `cache-01` + `mq-01` cluster |
| Replatform → managed service | `cache-01` → ElastiCache, `mq-01` → Amazon MQ, `nfs-01` → EFS |
| SQL Server → Aurora + schema conversion | `contoso-sql-01` (routes because it is SQL Server — the live app's MySQL did not) |
| .NET Framework → .NET | `contoso-web-01`, `contoso-app-01/02`, `contoso-worker-01` |
| Java 8 → 17 | `catalog-svc-01` |
| COBOL / mainframe | `finance-batch-01` |

The code behind the last four rows lives in [`../modernization/`](../modernization).
