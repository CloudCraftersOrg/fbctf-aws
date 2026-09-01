#!/bin/bash
# Load modernization/sqlserver-schema into the RDS instance and create the
# read-only login AWS Transform's SQL Server job connects with. Logs to
# /var/log/user-data.log; reach the host with SSM. Idempotent-ish: re-running
# the DDL against an existing schema errors harmlessly and the run continues.
set -uxo pipefail
exec > >(tee -a /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

dnf install -y jq
curl -fsSL https://packages.microsoft.com/config/rhel/9/prod.repo -o /etc/yum.repos.d/mssql-release.repo
ACCEPT_EULA=Y dnf install -y msodbcsql18 mssql-tools18
SQLCMD=/opt/mssql-tools18/bin/sqlcmd

SECRET=$(aws secretsmanager get-secret-value --region ${region} --secret-id "${secret_arn}" --query SecretString --output text)
DBADMIN=$(echo "$SECRET" | jq -r .username)
DBPASS=$(echo "$SECRET" | jq -r .password)
DB=${db_address}

# -I: QUOTED_IDENTIFIER ON (the computed column referencing a UDF needs it).
run() { "$SQLCMD" -S "$DB" -U "$DBADMIN" -P "$DBPASS" -C -I -b "$@"; }

# Wait for the instance to accept connections.
for i in $(seq 1 30); do
  run -Q "SELECT 1" && break
  echo "waiting for SQL Server ($i/30)"; sleep 20
done

mkdir -p /opt/schema
aws s3 cp "s3://${schema_bucket}/" /opt/schema/ --recursive --region ${region}

run -i /opt/schema/01_tables.sql          || echo "01_tables returned non-zero (may already exist)"
run -i /opt/schema/02_programmability.sql || echo "02_programmability returned non-zero"
run -i /opt/schema/03_seed.sql            || echo "03_seed returned non-zero"

# Read-only login for Transform: VIEW DEFINITION + VIEW DATABASE STATE (per the
# SQL Server modernization prerequisites).
run -Q "IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'transform_ro')
        CREATE LOGIN transform_ro WITH PASSWORD = '${ro_password}', CHECK_POLICY = OFF;"
run -d Scoreboard -Q "
  IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'transform_ro')
    CREATE USER transform_ro FOR LOGIN transform_ro;
  GRANT VIEW DEFINITION TO transform_ro;
  GRANT VIEW DATABASE STATE TO transform_ro;
"

echo "sqlmod schema load complete $(date -u +%FT%TZ)"
echo "  server   : $DB,1433"
echo "  database : Scoreboard"
echo "  ro login : transform_ro"
