#!/bin/bash
# Bring up SQL Server 2022 as a container on this host, then load
# modernization/sqlserver-schema and create the read-only login AWS Transform's
# SQL Server job connects with. Logs: /var/log/user-data.log (reach the host with
# SSM). Re-runnable: the DDL errors harmlessly against an existing schema.
set -uxo pipefail
exec > >(tee -a /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

dnf install -y docker jq
systemctl enable --now docker

curl -fsSL https://packages.microsoft.com/config/rhel/9/prod.repo -o /etc/yum.repos.d/mssql-release.repo
ACCEPT_EULA=Y dnf install -y msodbcsql18 mssql-tools18
SQLCMD=/opt/mssql-tools18/bin/sqlcmd

SA_PW=$(aws secretsmanager get-secret-value --region ${region} --secret-id "${sa_secret_arn}" --query SecretString --output text | jq -r .password)

mkdir -p /var/opt/mssql
chown 10001:0 /var/opt/mssql
docker pull ${mssql_image}
docker run -d --name mssql --restart unless-stopped \
  -e ACCEPT_EULA=Y -e MSSQL_PID=Express -e "MSSQL_SA_PASSWORD=$SA_PW" \
  -p 1433:1433 -v /var/opt/mssql:/var/opt/mssql \
  ${mssql_image}

# -C trust self-signed TLS, -I QUOTED_IDENTIFIER ON (a computed column references
# a scalar UDF), -b exit non-zero on error.
run() { "$SQLCMD" -S localhost -U sa -P "$SA_PW" -C -I -b "$@"; }

for i in $(seq 1 30); do
  run -Q "SELECT @@VERSION" && break
  echo "waiting for SQL Server ($i/30)"; sleep 10
done

mkdir -p /opt/schema
aws s3 cp "s3://${schema_bucket}/" /opt/schema/ --recursive --region ${region}

run -i /opt/schema/01_tables.sql          || echo "01_tables returned non-zero (may already exist)"
run -i /opt/schema/02_programmability.sql || echo "02_programmability returned non-zero"
run -i /opt/schema/03_seed.sql            || echo "03_seed returned non-zero"

# Read-only login for Transform: VIEW DEFINITION + VIEW DATABASE STATE.
run -Q "IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'transform_ro')
        CREATE LOGIN transform_ro WITH PASSWORD = '${ro_password}', CHECK_POLICY = OFF;"
run -d Scoreboard -Q "
  IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'transform_ro')
    CREATE USER transform_ro FOR LOGIN transform_ro;
  GRANT VIEW DEFINITION TO transform_ro;
  GRANT VIEW DATABASE STATE TO transform_ro;
"

IP=$(curl -fsS -H "X-aws-ec2-metadata-token: $(curl -fsS -X PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 60')" http://169.254.169.254/latest/meta-data/local-ipv4)
echo "sqlmod ready $(date -u +%FT%TZ)"
echo "  server   : $IP,1433"
echo "  database : Scoreboard"
echo "  ro login : transform_ro"
