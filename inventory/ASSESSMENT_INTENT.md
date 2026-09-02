# Assessment intent — 14-server portfolio, migrate and modernize

Treat this as a **production, always-on** estate for an internal Capture-the-Flag
platform: a public scoreboard, its scoring services, a challenge catalog, a
finance batch job, and the self-managed middleware they depend on. Assess it for
**migration and modernization** — right-size it, make it resilient, remove the
end-of-life foundations, and move self-managed services to managed equivalents.
This is not a lift-and-shift.

Utilization samples are from a short window and under-represent sustained load.
Size on **peak CPU/RAM with headroom**.

## The estate (14 servers, in the upload)

| Group | Servers | Notes |
|---|---|---|
| **Public web app (fbctf)** | `i-0422e26203cb709b2` (Ubuntu 16.04, nginx), `i-0d6b944117ba6302b` (Ubuntu 16.04, HHVM 3.21 Hack/PHP) | live app. EOL OS. HHVM has no ARM64 build and no security patches since 2019. |
| **Scoreboard .NET tier** | `contoso-web-01` (Win 2016, IIS + ASP.NET MVC 5), `contoso-app-01` / `-02` (Win 2019, .NET Framework 4.8 Web API + WCF), `contoso-worker-01` (Win 2012 R2, .NET FW 4.5 queue worker) | web-01 is heavily over-provisioned (32 GB RAM @ 14 % avg) and a single node. worker OS is EOL. |
| **Databases** | `contoso-sql-01` (Win 2019, SQL Server 2017 Standard, 2 TB @ 18 %), `contoso-sql-rpt-01` (Win 2019, SQL Server 2017 reporting replica, 32 GB @ 12 % avg) | sql-01 is single-AZ, no HA. rpt-01 is under-utilised. |
| **Catalog / batch** | `catalog-svc-01` (RHEL 7.9, Java 8 Spring Boot 2.3), `finance-batch-01` (RHEL 8.8, GnuCOBOL nightly rollup) | RHEL 7 is EOL. batch load is spiky (peak 92 / avg 8). |
| **Self-managed middleware** | `cache-01` (AL2, Redis 6), `mq-01` (Ubuntu 16.04, RabbitMQ 3.6), `nfs-01` (AL2, NFS export, 4 TB @ 8 %) | mq-01 OS is EOL. nfs volume is 4 TB, 8 % used. |
| **CI** | `ci-01` (AL2, Jenkins) | idle nights and weekends (avg 3 % CPU). |

Dependency edges are in the network-connections file zipped alongside this
inventory (web→app, app→sql/cache/mq/catalog, worker→mq/sql, sql→rpt replication,
batch→nfs/sql, ci→app/catalog).

## Managed-service dependencies of the fbctf app (assess separately, not servers)

RDS for MySQL 8.0 `db.t3.small` single-AZ, backups off; ElastiCache memcached
`cache.t3.micro`; internet-facing ALB (HTTP only, no TLS/WAF); internal NLB
(TCP:9000 FastCGI); one single-AZ NAT gateway; 3 Secrets Manager secrets.

## Requested target state (the "after")

- **Right-sizing:** downsize the over-provisioned web/report tiers; flag idle
  `ci-01` for **retire** (→ CodeBuild); shrink the 2 TB and 4 TB near-empty
  volumes.
- **Resilience:** Multi-AZ for `contoso-sql-01`; 2-AZ compute for the web tiers;
  everything currently sits in one AZ.
- **End-of-life:** replace Ubuntu 16.04, Windows Server 2012 R2, RHEL 7.
- **Self-managed → managed:** `cache-01` → ElastiCache, `mq-01` → Amazon MQ,
  `nfs-01` → EFS.
- **Databases:** `contoso-sql-01` / `-rpt-01` → **Aurora PostgreSQL** (primary +
  reader endpoint), schema + stored-proc conversion.
- **Code:** `contoso-*` .NET Framework → **.NET 8**; `catalog-svc-01` **Java 8 →
  17**; `finance-batch-01` **COBOL → Java**.
- **fbctf app:** containerize on **ECS Fargate** (2 tasks / 2 AZs, Graviton
  where the runtime allows — nginx yes, HHVM no); RDS MySQL right-sized +
  Multi-AZ; drop the NLB and memcached; CloudFront + WAF + ACM at the edge;
  eliminate the NAT gateway with VPC endpoints.
- **Purchasing:** runs 24/7 — compare On-Demand vs a 1-year Compute Savings Plan
  vs RIs.
- **Governance:** budget + anomaly alerts; tag every resource.

## What the assessment should produce

1. Inventory readiness + OS end-of-support breakdown.
2. Dependency graph → **move groups** → **wave plan** (sql-01 and its replica
   sequence together; the fbctf pair moves as one; `ci-01` last / dropped).
3. Right-sized EC2/EBS recommendations (rehost baseline) **plus** a modernization
   scenario per group.
4. Managed-services cost lines (RDS / ElastiCache / ALB / NLB / NAT) — current
   vs modernized.
5. Side-by-side **TCO**: current 24/7 spend vs rehost-right-sized vs modernize,
   with On-Demand / Savings Plan / RI pricing.
6. Resilience and sustainability assessment.
7. An explicit statement of what AWS Transform can and cannot modernize:
   - **Can:** .NET Framework, Java 8, COBOL, SQL Server schema — see the
     `modernization/` fixtures.
   - **Cannot:** the fbctf app's **PHP/Hack** — no supported code path; the
     durable fix is a rewrite, flagged as a follow-on.

## TCO baseline (fbctf app, list price, 24/7)

~$190/month: EC2 ~$46 + NAT ~$33 + NAT EIP ~$4 + ALB ~$16 + 2 public IPv4 ~$7 +
internal NLB ~$16 + RDS ~$27 + ElastiCache ~$12 + EBS ~$5 + Secrets Manager ~$1
+ CloudWatch ~$4. Set a per-server on-prem-equivalent baseline for the
`contoso-*` / `catalog` / `batch` hosts in chat.
