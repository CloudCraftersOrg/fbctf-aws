# Simulated source estate — Transform assessment input

The live fbctf app (`environments/demo`) is one workload. A migration assessment
needs an *estate*: enough servers, operating systems and dependencies that
right-sizing, move groups, wave planning and TCO have something to chew on, and
enough variety that every assessment finding shows up at least once.

This directory is that estate, expressed as **data, not infrastructure** — it
costs nothing and is never deployed. `generate.py` turns it into the two CSVs
AWS Transform's Migration Portfolio Assessment (MPA) imports.

## Files

| File | Purpose |
|---|---|
| `fleet.yaml` | 14 servers. The two `i-*` hosts mirror the live app (same IDs/OS/utilisation as the validated upload); the rest are synthetic. Each carries a `signal:` line naming the finding it exercises. |
| `connections.yaml` | Server-to-server dependency edges. Every synthetic host has at least one edge, so nothing lands in a trivial one-host wave. |
| `generate.py` | Emits `out/mpa_servers.csv` + `out/network_connections.csv`. `--check` validates without writing. |
| `requirements.txt` | `PyYAML` — the only dependency. |

## Generate the import

```sh
python3 -m pip install -r inventory/requirements.txt
python3 inventory/generate.py
# -> inventory/out/mpa_servers.csv        (14 rows)
# -> inventory/out/network_connections.csv (18 rows)
```

`out/` is gitignored — regenerate it, don't commit it.

## Feed it to Transform

1. AWS Transform console → **Migrate** → new **assessment** → data source
   **Migration Portfolio Assessment (import)**.
2. Upload `mpa_servers.csv` to the **Servers** slot and
   `network_connections.csv` to the **Network connections** slot.
3. Paste `ASSESSMENT_INTENT.md` (kept with the validated upload in
   `~/aws-personal/workdir`, or write a fresh one) into the assessment chat as
   the modernization brief.

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
