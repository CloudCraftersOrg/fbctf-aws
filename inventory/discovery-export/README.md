# fbctf discovery export — input for an AWS Transform assessment

**Generated:** 2026-08-27 ~22:40Z
**Target application:** `facebookarchive/fbctf` (Facebook CTF, Hack/HHVM, archived 2018) running as the "before" state for an AWS Transform modernization demo
**Source infra:** `CloudCraftersOrg/fbctf-aws` deployed to AWS account `337058058699`, region `us-east-1`
**Collected by:** read-only AWS APIs + CloudWatch + `AWS-RunShellScript` over SSM, profile `personal-transform`

---

## What this is

The AWS Transform **discovery tool** is an on-prem OVA/VHD appliance that inventories VMware/Hyper-V
estates. It has nothing to point at here — fbctf runs on EC2, not a hypervisor. This package is the
**equivalent discovery performed directly against the live AWS resources**, formatted to match the
discovery tool's export schema (`discovery_tool_export.zip` — see
<https://docs.aws.amazon.com/transform/latest/userguide/discovery-tool-data-collection.html>) so it can
be uploaded to a Transform **Migration assessment** the same way a real export would.

Upload target: <https://docs.aws.amazon.com/transform/latest/userguide/transform-app-assessments.html>
(Transform accepts RVTools exports, CMDB dumps, discovery-tool exports, or "notes from your own
discovery process" — this is the last category, structured.)

## Files

| File | Discovery-tool equivalent | Rows |
|---|---|---|
| `server_inventory.csv` | `server_inventory.csv` | 2 |
| `server_performance_metrics.csv` | `server_performance_metrics.csv` | 2 |
| `server_storage_performance.csv` | `server_storage_performance.csv` | 2 |
| `storage_config.csv` | `storage_config.csv` | 2 |
| `network_interfaces.csv` | `network_interfaces.csv` | 2 |
| `process_metrics.csv` | `process_metrics.csv` | 17 |
| `network_connections.csv` | network connections module | 10 edges |
| `mpa_exports/servers.csv` | MPA primary server file (inside the zip) | 2 |
| `mpa_exports/connections.csv` | MPA server-to-server connections | 3 |
| `managed_dependencies.json` | *(no equivalent — see below)* | — |
| `infrastructure_topology.json` | nested vCenter JSON | — |

Brief: use `../ASSESSMENT_INTENT.md` (the fbctf `i-*` rows are already in it).
Run steps: [`../../docs/demo-runbook.md`](../../docs/demo-runbook.md) — this is
the "same assessment, discovered live" half of the fbctf segment (Layer C).

## Scope and fidelity notes — read before using this

1. **2 servers, not more.** A real discovery-tool run against this stack sees exactly two OS instances:
   `fbctf-demo-web` (nginx) and `fbctf-demo-app` (HHVM). RDS MySQL and ElastiCache memcached are managed
   services with no OS to reach — and the tool's database modules cover **SQL Server and Oracle only**,
   never MySQL. MySQL appears in a real export only as a `mysql` client process and a network edge.
   The full RDS/ElastiCache/ELB/NAT picture is in `managed_dependencies.json` — **that file has no
   discovery-tool equivalent**; it is control-plane data a Transform assessment still needs.

2. **Utilization is not representative.** The instances launched 2026-08-27 18:56Z (web) and 20:55Z
   (app). The metrics window is **1.8–3.6 hours**, almost entirely boot-time provisioning plus idle.
   A real assessment needs **14–30 days**. Every CPU/IOPS/network "peak" in these files is a one-time
   boot event (schema import, package installs, tarball pulls). Steady-state load is near-zero — this
   is a scoreboard for a handful of teams. Treat the numbers as "confirms it is tiny", not as a
   right-sizing basis.

3. **Hypervisor fields.** `hypervisor_type` etc. are filled with the AWS/EC2 equivalent
   (instance id as `hypervisor_object_id`, `us-east-1a` as `hypervisor_hostname`). `cluster_name`
   is the Auto Scaling group.

4. **Network connections.** The discovery tool only records edges where **both endpoints are
   inventoried servers**. Only `web -> app` (via the NLB) qualifies. Edges to RDS, memcached, the
   load balancers, and the internet are included here with `evidence` = `observed` / `inferred` /
   `transient` and would appear in a real export only under "private address collection" (RFC 1918) or
   not at all.

5. **No SQL Server / Oracle CSVs** (`oracle_data_*.csv`, SQL Server data) — not applicable.

## Key discovered facts

- **OS:** both hosts Ubuntu 16.04.7 LTS (xenial), kernel 4.4.0-1128-aws. EOL; unpatched since ~2021.
  AMI `ami-0b0ea68c435eb488d` was deprecated by Canonical 2023-09-29.
- **Runtime:** HHVM 3.21.11 (2017). HHVM dropped PHP/Hack-for-PHP support in 2019 — **no security
  patches will ever ship for this runtime again**. No ARM64 build → the app tier cannot move to
  Graviton without leaving HHVM.
- **Compute:** web `t3.small` (1.9 GiB), app `t3.medium` (3.8 GiB). Both burstable in **`unlimited`**
  credit mode (AWS default; launch templates don't set it). Both idle at ~1% CPU / ~300 MB RSS.
  app was sized `t3.medium` for **build-time** Composer RAM — now moot, the build is pre-baked into
  the S3 tarball.
- **Data:** RDS MySQL 8.0.46 `db.t3.small`, single-AZ, **backups off, deletion protection off,
  Performance Insights off**. Dataset ~1.6 GiB. Avg 0.07 connections.
- **Cache:** ElastiCache memcached `cache.t3.micro`, 1 node. **~54 KB used, ~8 items.** Effectively
  unused.
- **Edge:** internet-facing ALB, **HTTP only, no TLS**. Session cookie forced non-`Secure`
  (`SessionUtils.php` patch) so credentials cross the internet in cleartext. No WAF.
- **Topology:** 2-AZ subnet layout but **everything runs in us-east-1a** (both instances, the single
  NAT, RDS, memcached). No S3 gateway endpoint — the 36.5 MB prebuilt tarball + 31 MB HHVM debs pull
  through the NAT gateway on every instance launch.
- **Tagging:** ASG instances + EBS volumes carry only `Name` (provider `default_tags` don't reach
  ASG-launched resources) → the largest cost slice is invisible to tag-based FinOps reporting.

## Modernization + FinOps

A Transform assessment produces the right-sizing recommendations, wave plan, and TCO from this input.
The human-readable assessment is the companion report `fbctf-assessment.html`; the full FinOps plan
(tiered, with citations) is `fbctf-finops.md`. Headlines:

- This stack should not run 24/7 — it is a demo. `terraform destroy` between sessions gets it under
  ~$10/mo versus ~$175–210/mo on-demand. **Stopping the instances alone only reaches ~$59/mo** — the
  NAT gateway, both load balancers, the EIPs and the EBS volumes keep billing.
- ~$77/mo is standing networking scaffolding (NAT + NAT EIP + ALB + 2× ALB public IPv4 + NLB). The
  public-IPv4 charge alone is ~$11/mo.
- Right-sizing without re-architecture (t3a/t4g instances, db.t4g.micro, drop NLB + cache, NAT via
  endpoints, CloudFront instead of ALB) takes 24/7 to ~$70–90/mo.
- Perf Insights is **not** available on db.t4g.micro/db.t3.small — Database Insights Standard (free) is
  what applies.
