#!/bin/bash
# Oracle Database 21c XE as a container on this host, then load the Contoso
# Catalog schema (sequence + trigger + PL/SQL package + view) and a read-only
# user for AWS Transform. Logs: /var/log/user-data.log (reach the host with SSM).
set -uxo pipefail
exec > >(tee -a /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

dnf install -y docker jq
systemctl enable --now docker

SYS_PW=$(aws secretsmanager get-secret-value --region ${region} --secret-id "${sys_secret_arn}" --query SecretString --output text | jq -r .password)
APP_JSON=$(aws secretsmanager get-secret-value --region ${region} --secret-id "${app_secret_arn}" --query SecretString --output text)
APP_USER=$(echo "$APP_JSON" | jq -r .username)
APP_PW=$(echo "$APP_JSON" | jq -r .password)
RO_PW=$(echo "$APP_JSON" | jq -r .ro_password)

mkdir -p /opt/oracle/oradata && chmod 777 /opt/oracle/oradata
docker pull ${oracle_image}
docker run -d --name oracle --restart unless-stopped \
  -p 1521:1521 \
  -e ORACLE_PASSWORD="$SYS_PW" \
  -e APP_USER="$APP_USER" -e APP_USER_PASSWORD="$APP_PW" \
  -v /opt/oracle/oradata:/opt/oracle/oradata \
  ${oracle_image}

echo "waiting for Oracle to open XEPDB1..."
for i in $(seq 1 60); do
  if docker exec oracle bash -lc "echo 'SELECT 1 FROM dual;' | sqlplus -s -L $APP_USER/$APP_PW@localhost:1521/XEPDB1" 2>/dev/null | grep -q '^ *1'; then
    echo "Oracle ready ($i)"; break
  fi
  sleep 10
done

mkdir -p /opt/schema
aws s3 cp "s3://${artifacts_bucket}/schema/" /opt/schema/ --recursive --region ${region}
docker cp /opt/schema oracle:/tmp/schema

run_app() { docker exec oracle bash -lc "sqlplus -s -L $APP_USER/$APP_PW@localhost:1521/XEPDB1 @/tmp/schema/$1"; }
run_app 01_schema.sql || echo "01_schema returned non-zero"
run_app 02_seed.sql   || echo "02_seed returned non-zero"

# Read-only user for AWS Transform (schema conversion assessment).
docker exec oracle bash -lc "sqlplus -s -L system/$SYS_PW@localhost:1521/XEPDB1 <<SQL
CREATE USER transform_ro IDENTIFIED BY \"$RO_PW\";
GRANT CREATE SESSION TO transform_ro;
GRANT SELECT ANY DICTIONARY TO transform_ro;
GRANT SELECT ANY TABLE TO transform_ro;
EXIT
SQL"

IP=$(curl -fsS -H "X-aws-ec2-metadata-token: $(curl -fsS -X PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 60')" http://169.254.169.254/latest/meta-data/local-ipv4)
echo "oramod ready $(date -u +%FT%TZ)"
echo "  service : $IP:1521/XEPDB1"
echo "  app user: $APP_USER   ro user: transform_ro"
