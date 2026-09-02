# sqlmod — the live SQL Server estate

The demo's live application stack: one **SQL Server 2022** on EC2 and two real
apps that use it. It is what the discovery tool inventories, what the .NET job
modernizes, and what the **full agentic SQL Server → Aurora** job reads through
the DMS replication instance Transform creates in this VPC.

## What it creates

| | |
|---|---|
| VPC (`modules/network`) | `10.40.0.0/16`, **2-AZ** subnets (the DMS replication subnet group needs ≥2 AZs) |
| SQL Server | `fbctf-sqlmod-sqlserver`, `t3.medium` AL2023 running the official `mssql/server:2022` container; loads `modernization/sqlserver-schema/*.sql` (DB `Scoreboard`) and creates the `transform_ro` login (`VIEW DEFINITION` + `VIEW DATABASE STATE`). `sa` in Secrets Manager `fbctf-sqlmod/sa`. |
| Contoso Scoreboard | `fbctf-sqlmod-app`, Windows Server 2022 + IIS, **ASP.NET Web Forms on .NET Framework 4.8** ([`app/`](app/)). Public EIP on `:80` (`app_allow_cidr`). WinRM + a `discovery` local admin for the discovery tool (secret `fbctf-sqlmod/app-winrm`). |
| Project Nami | `fbctf-sqlmod-wordpress`, Ubuntu 22.04 + Apache + PHP `pdo_sqlsrv`, **WordPress on SQL Server**. Public EIP on `:80` (`wordpress_allow_cidr`). Admin login in `fbctf-sqlmod/wordpress-admin`. |
| S3 bucket `fbctf-sqlmod-schema-*` | staging for the schema files and the app zip |

`1433` is open to the whole VPC CIDR, so Transform's DMS instance reaches it
wherever Transform places it. SSH / WinRM are open only to `discovery_cidr`
(the discovery-collector VPC, `10.70.0.0/16` by default).

Both app hosts keep one SQL connection established and the site warm, so the
discovery tool captures the app→DB edges even in a short run.

## Prerequisite — Transform access mode

The SQL Server modernization job requires **IAM Identity Center** access mode for
AWS Transform, chosen when Transform is first enabled and permanent. This account
is enabled with Identity Center. In an IAM-only account, fall back to offline
schema conversion (AWS SCT on `modernization/sqlserver-schema/*.sql`, `$0`).

## Run

```sh
cp environments/sqlmod/terraform.tfvars.example environments/sqlmod/terraform.tfvars
# edit transform_ro_password
make apply ENV=sqlmod                 # ~10 min; the app hosts finish bootstrapping ~5 min after
terraform -chdir=environments/sqlmod output
```

Outputs: `sql_server_address` / `sql_server_port` / `database_name` /
`transform_login` for the SQL Server job, `dms_subnet_ids` + `vpc_id` for its
landing zone, `app_url` and `wordpress_url` for the two apps, and the instance
IDs for SSM (`/var/log/user-data.log`, `C:\app-setup.log`).

Feed the SQL Server job the **.NET 8 output of the .NET modernization job** run
on [`app/`](app/) — see [`app/README.md`](app/README.md) for packaging the source.

```sh
make destroy ENV=sqlmod               # after the demo
```

## Cost

Three on-demand instances (`t3.medium` ×2, `t3.small`) + 2 EIPs ≈ **$0.20/hr**,
`$0` destroyed. Add whatever Transform's DMS instance and the Aurora target cost
while a job runs; delete those from the Transform job — `terraform destroy` only
removes what this root owns.
