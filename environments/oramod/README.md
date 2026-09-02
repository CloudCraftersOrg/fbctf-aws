# oramod — the live Oracle estate

The third app in the demo stack: **Contoso Catalog**, a Spring Boot 2.7 / Java 8
service on one EC2, talking to **Oracle Database 21c XE** on another. A textbook
legacy enterprise workload for AWS Transform, and a three-way target:

| Path | What Transform does |
|---|---|
| **Java 8 → 17** (`atx AWS/java-version-upgrade`) | Spring Boot 2.7 → 3, `javax.persistence` → `jakarta`, `WebSecurityConfigurerAdapter` → `SecurityFilterChain`, `RestTemplate` → `RestClient`, `SimpleDateFormat` → `java.time`, JUnit 4 → 5 |
| **Oracle → Aurora PostgreSQL** | `PRODUCT_SEQ` + `trg_products_bi` → identity; `catalog_pkg` PL/SQL package → PL/pgSQL; `VW_CATALOG_SUMMARY` view; `VIRTUAL` column; `FROM dual` |
| **Data layer** | the JPA `@SequenceGenerator` and native `@Query` calls against `catalog_pkg.restock` / `VW_CATALOG_SUMMARY`, rewritten alongside the schema |

## What it creates

| | |
|---|---|
| VPC (`modules/network`) | `10.50.0.0/16`, **2-AZ** subnets (Transform's DMS replication subnet group needs ≥2 AZs) |
| Oracle | `fbctf-oramod-oracle`, `t3.medium` AL2023 running `gvenzl/oracle-xe:21-slim`; loads [`schema/`](schema/) into PDB `XEPDB1`, creates the `catalog` app user and the `transform_ro` reader. `sys` in Secrets Manager `fbctf-oramod/oracle-sys`; app + `transform_ro` credentials in `fbctf-oramod/catalog-app`. |
| Contoso Catalog | `fbctf-oramod-app`, `t3.small` AL2023, systemd-run Spring Boot jar built at boot from [`app/`](app/). Public EIP on `:80` (`app_allow_cidr`). Thymeleaf UI + JSON at `/api/products`. |
| S3 bucket `fbctf-oramod-artifacts-*` | staging for the schema files and `app.zip` |

`1521` is open to the whole VPC CIDR for Transform's DMS instance. SSH and
Oracle Net are also open to `discovery_cidr` (the discovery-collector VPC) so
the discovery tool's Oracle module can read `XEPDB1` as `transform_ro`.

## Run

```sh
make apply ENV=oramod                 # ~8 min; Oracle XE takes a few more minutes to open the PDB
terraform -chdir=environments/oramod output
```

Outputs: `oracle_address` / `transform_ro_user` / `app_secret_arn` (holds the
`transform_ro` password) for the Oracle job, `dms_subnet_ids` + `vpc_id` for its
landing zone, `app_url`, and the instance IDs for SSM (`/var/log/user-data.log`).

```sh
make destroy ENV=oramod               # after the demo
```

## Cost

`t3.medium` + `t3.small` + 1 EIP ≈ **$0.15/hr**, `$0` destroyed. Add Transform's
DMS instance and the Aurora target while a job runs; delete those from the
Transform job — `terraform destroy` only removes what this root owns.
