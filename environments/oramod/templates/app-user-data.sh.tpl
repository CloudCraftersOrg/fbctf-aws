#!/bin/bash
# Build and run the Contoso Catalog app (Spring Boot 2.7 / Java 8) against the
# Oracle host. Logs: /var/log/user-data.log (reach the host with SSM).
set -uxo pipefail
exec > >(tee -a /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

dnf install -y java-1.8.0-amazon-corretto-devel jq tar gzip unzip
MVN=3.9.9
curl -fsSL -o /tmp/mvn.tgz "https://archive.apache.org/dist/maven/maven-3/$MVN/binaries/apache-maven-$MVN-bin.tar.gz"
tar -xzf /tmp/mvn.tgz -C /opt
ln -sf /opt/apache-maven-$MVN/bin/mvn /usr/bin/mvn

useradd -r -s /sbin/nologin catalog || true
install -d -o catalog -g catalog /opt/catalog

aws s3 cp "s3://${artifacts_bucket}/app.zip" /tmp/app.zip --region ${region}
mkdir -p /tmp/app && unzip -q -o /tmp/app.zip -d /tmp/app
( cd /tmp/app && JAVA_HOME=/usr/lib/jvm/java-1.8.0-amazon-corretto mvn -q -B package -DskipTests )
cp /tmp/app/target/catalog.jar /opt/catalog/catalog.jar
chown catalog:catalog /opt/catalog/catalog.jar

APP_JSON=$(aws secretsmanager get-secret-value --region ${region} --secret-id "${app_secret_arn}" --query SecretString --output text)
DB_USER=$(echo "$APP_JSON" | jq -r .username)
DB_PW=$(echo "$APP_JSON" | jq -r .password)
EDITOR_PW=$(echo "$APP_JSON" | jq -r .editor_password)

cat >/etc/systemd/system/catalog.service <<UNIT
[Unit]
Description=Contoso Catalog
After=network-online.target
Wants=network-online.target

[Service]
User=catalog
AmbientCapabilities=CAP_NET_BIND_SERVICE
Environment=SERVER_PORT=80
Environment=CATALOG_DB_URL=jdbc:oracle:thin:@${oracle_host}:1521/XEPDB1
Environment=CATALOG_DB_USER=$DB_USER
Environment=CATALOG_DB_PASSWORD=$DB_PW
Environment=CATALOG_EDITOR_PASSWORD=$EDITOR_PW
ExecStart=/usr/lib/jvm/java-1.8.0-amazon-corretto/bin/java -jar /opt/catalog/catalog.jar
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now catalog

for i in $(seq 1 30); do
  curl -fsS -o /dev/null http://localhost/ && break
  echo "waiting for catalog ($i/30)"; sleep 10
done
IP=$(curl -fsS -H "X-aws-ec2-metadata-token: $(curl -fsS -X PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 60')" http://169.254.169.254/latest/meta-data/public-ipv4)
echo "catalog ready $(date -u +%FT%TZ) - http://$IP/  (editor login: editor / see fbctf-oramod/catalog-app)"
