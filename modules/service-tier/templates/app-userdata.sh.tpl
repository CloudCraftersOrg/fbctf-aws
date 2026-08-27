#!/bin/bash
# fbctf app tier (HHVM) boot provisioning. Strategy (requirements §3.3):
#   1. prebuilt tarball from S3 (vendor/ + node_modules + grunt output baked in)
#   2. the app's own provision.sh (-m prod -R, multi-server hhvm) — with the
#      vendored-HHVM-debs fallback if dl.hhvm.com is gone
#   3. re-render settings.ini with real credentials (provision hardcodes ctf/ctf)
#   4. guarded one-shot DB bootstrap: schema + app user + admin row
# Log: /var/log/user-data.log
set -euxo pipefail
exec > /var/log/user-data.log 2>&1

export DEBIAN_FRONTEND=noninteractive
export HOME=/root
REGION="${region}"
BUCKET="${artifacts_bucket}"
PREBUILT_KEY="${prebuilt_key}"
CTF_PATH=/var/www/fbctf

# --- base tooling + AWS CLI v2 ---
apt-get update
apt-get install -y curl unzip jq ca-certificates apt-transport-https \
  software-properties-common mysql-client
curl -sSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/awscli.zip
unzip -q /tmp/awscli.zip -d /tmp && /tmp/aws/install

param() { aws ssm get-parameter --name "/fbctf/$1" --query Parameter.Value --output text --region "$REGION"; }
secret() { aws secretsmanager get-secret-value --secret-id "$1" --query SecretString --output text --region "$REGION"; }

DB_HOST=$(param db_endpoint)
MC_HOST=$(param mc_endpoint)
MASTER_JSON=$(secret "$(param db_master_secret_arn)")
APP_JSON=$(secret "$(param db_app_secret_arn)")
ADMIN_JSON=$(secret "$(param admin_secret_arn)")
MASTER_USER=$(echo "$MASTER_JSON" | jq -r .username)
MASTER_PW=$(echo "$MASTER_JSON" | jq -r .password)
APP_USER=$(echo "$APP_JSON" | jq -r .username)
APP_PW=$(echo "$APP_JSON" | jq -r .password)
ADMIN_PW=$(echo "$ADMIN_JSON" | jq -r .password)

# --- prebuilt app tarball ---
mkdir -p /root/fbctf
aws s3 cp "s3://$BUCKET/$PREBUILT_KEY" /tmp/app.tgz --region "$REGION"
tar xzf /tmp/app.tgz -C /root/fbctf

# --- the app's own provisioning (hhvm server type) ---
# Fallback: if dl.hhvm.com has vanished, install HHVM from the vendored .debs
# and rerun provision (every step in it is idempotent: rsync, apt, sed).
cd /root/fbctf
run_provision() {
  ./extra/provision.sh -m prod -R --multiple-servers --server-type hhvm \
    --mysql-server "$DB_HOST" --cache-server "$MC_HOST" \
    -s /root/fbctf -d "$CTF_PATH"
}
if ! run_provision; then
  echo "provision failed — trying vendored HHVM debs fallback"
  aws s3 cp "s3://$BUCKET/vendored/hhvm-debs-xenial-3.21.tgz" /tmp/hhvm-debs.tgz --region "$REGION"
  mkdir -p /tmp/hhvm-debs && tar xzf /tmp/hhvm-debs.tgz -C /tmp/hhvm-debs
  dpkg -i /tmp/hhvm-debs/*.deb || apt-get -f install -y
  run_provision
fi

# --- settings.ini with real credentials (provision wrote ctf/ctf) ---
sed -e "s/DBHOST/$DB_HOST/g" -e "s/DATABASE/fbctf/g" \
    -e "s/MYUSER/$APP_USER/g" -e "s/MYPWD/$APP_PW/g" -e "s/MCHOST/$MC_HOST/g" \
    "$CTF_PATH/extra/settings.ini.example" > "$CTF_PATH/settings.ini"
chown www-data:www-data "$CTF_PATH/settings.ini"
chmod 640 "$CTF_PATH/settings.ini"

# --- guarded one-shot DB bootstrap (§3.6) ---
# The configuration table is seeded by schema.sql, so this guard flips exactly
# once. desired_capacity=1 keeps the race window theoretical for the demo.
export MYSQL_PWD="$MASTER_PW"
if ! mysql -h "$DB_HOST" -u "$MASTER_USER" -N -e "SELECT 1 FROM fbctf.configuration LIMIT 1" >/dev/null 2>&1; then
  echo "DB empty — running bootstrap"
  for f in schema countries logos; do
    aws s3 cp "s3://$BUCKET/sql/$f.sql" "/tmp/$f.sql" --region "$REGION"
    mysql -h "$DB_HOST" -u "$MASTER_USER" fbctf < "/tmp/$f.sql"
  done
  mysql -h "$DB_HOST" -u "$MASTER_USER" <<SQL
CREATE USER IF NOT EXISTS '$APP_USER'@'%' IDENTIFIED WITH mysql_native_password BY '$APP_PW';
GRANT ALL PRIVILEGES ON fbctf.* TO '$APP_USER'@'%';
FLUSH PRIVILEGES;
SQL
  HASH=$(hhvm -f "$CTF_PATH/extra/hash.php" "$ADMIN_PW")
  mysql -h "$DB_HOST" -u "$MASTER_USER" fbctf <<SQL
DELETE FROM teams WHERE name='admin' AND admin=1;
INSERT INTO teams (id, name, password_hash, admin, protected, logo, created_ts)
  VALUES (1, 'admin', '$HASH', 1, 1, 'admin', NOW());
SQL
else
  echo "DB already bootstrapped — skipping"
fi

# --- demo branding (idempotent, every boot): Spanish UI, EPAM org, custom
# byline + logo. The logo file ships inside the app tarball at
# src/static/img/custom-branding.png. Config is cached in memcached — flush
# so changes take effect immediately.
mysql -h "$DB_HOST" -u "$MASTER_USER" fbctf <<'SQL'
UPDATE configuration SET value='es' WHERE field='language';
UPDATE configuration SET value='EPAM' WHERE field='custom_org';
UPDATE configuration SET value='Powered By CloudCrafters' WHERE field='custom_byline';
UPDATE configuration SET value='1' WHERE field='custom_logo';
UPDATE configuration SET value='static/img/custom-branding.png' WHERE field='custom_logo_image';
SQL
printf 'flush_all\r\nquit\r\n' | timeout 5 bash -c "cat > /dev/tcp/$MC_HOST/11211" || true
unset MYSQL_PWD

# --- restart HHVM with final settings and verify ---
service hhvm restart
sleep 3
ss -lnt | grep -q ':9000 ' || (echo "HHVM not listening on 9000" && exit 1)

# --- CloudWatch agent (non-fatal: logging must never block the boot) ---
(
  set +e
  curl -sSL https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb -o /tmp/cwagent.deb
  dpkg -i /tmp/cwagent.deb
  cat > /opt/aws/amazon-cloudwatch-agent/etc/cw-config.json <<CFG
{"logs":{"logs_collected":{"files":{"collect_list":[
  {"file_path":"/var/log/hhvm/error.log","log_group_name":"/fbctf/hhvm","log_stream_name":"{instance_id}"},
  {"file_path":"/var/log/user-data.log","log_group_name":"/fbctf/user-data","log_stream_name":"app-{instance_id}"}
]}}}}
CFG
  /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/cw-config.json
) || echo "CloudWatch agent setup failed (non-fatal)"

echo "APP TIER BOOT COMPLETE"
