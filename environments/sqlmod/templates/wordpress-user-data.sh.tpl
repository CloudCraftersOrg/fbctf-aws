#!/bin/bash
# Project Nami (WordPress fork for SQL Server) on Ubuntu + Apache + PHP 8.1 with
# the Microsoft pdo_sqlsrv / sqlsrv driver, pointed at the sqlmod SQL Server.
# Logs: /var/log/user-data.log (reach the host with SSM).
set -uxo pipefail
exec > >(tee -a /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y apache2 unzip jq curl gnupg gcc make \
  php php-cli php-dev php-pear php-mbstring php-xml php-curl php-gd \
  unixodbc-dev libgssapi-krb5-2 awscli
PHPV=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')

curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor -o /usr/share/keyrings/microsoft-prod.gpg
. /etc/os-release
echo "deb [signed-by=/usr/share/keyrings/microsoft-prod.gpg] https://packages.microsoft.com/ubuntu/$VERSION_ID/prod $VERSION_CODENAME main" > /etc/apt/sources.list.d/mssql-release.list
apt-get update -y
ACCEPT_EULA=Y apt-get install -y msodbcsql18 mssql-tools18
SQLCMD=/opt/mssql-tools18/bin/sqlcmd

pecl channel-update pecl.php.net || true
printf "\n\n\n\n" | pecl install sqlsrv pdo_sqlsrv || pecl install -f sqlsrv pdo_sqlsrv
for m in sqlsrv pdo_sqlsrv; do echo "extension=$m.so" > /etc/php/$PHPV/mods-available/$m.ini; phpenmod $m; done
php -m | grep -i sqlsrv

SA_PW=$(aws secretsmanager get-secret-value --region ${region} --secret-id "${sa_secret_arn}" --query SecretString --output text | jq -r .password)
WP_PW=$(aws secretsmanager get-secret-value --region ${region} --secret-id "${wp_secret_arn}" --query SecretString --output text | jq -r .password)
SQLHOST=${sql_host}

sql() { "$SQLCMD" -S "$SQLHOST,1433" -U sa -P "$SA_PW" -C -b "$@"; }
for i in $(seq 1 30); do sql -Q "SELECT 1" && break; echo "waiting for SQL Server ($i/30)"; sleep 10; done
sql -Q "IF DB_ID('wordpress') IS NULL CREATE DATABASE wordpress;"
sql -Q "IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name='wp_app')
        CREATE LOGIN wp_app WITH PASSWORD='$WP_PW', CHECK_POLICY=OFF;"
sql -d wordpress -Q "
  IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name='wp_app')
    CREATE USER wp_app FOR LOGIN wp_app;
  ALTER ROLE db_owner ADD MEMBER wp_app;"

cd /tmp
curl -fsSL -o pn.zip "${projectnami_zip_url}"
unzip -q pn.zip
SRC=$(find /tmp -maxdepth 1 -type d -name 'projectnami*' | head -1)
rm -rf /var/www/html && mkdir -p /var/www/html
cp -a "$SRC"/. /var/www/html/

# ODBC Driver 18 defaults to Encrypt=yes and validates the cert; the mssql
# container serves a self-signed one. Project Nami's sqlsrv_connect() calls do
# not set TrustServerCertificate - add it.
sed -i "s/'ReturnDatesAsStrings'=>true,/'ReturnDatesAsStrings'=>true, 'TrustServerCertificate'=>true,/g" \
  /var/www/html/wp-includes/class-wpdb.php

cp /var/www/html/wp-config-sample.php /var/www/html/wp-config.php
sed -i \
  -e "s/database_name_here/wordpress/" \
  -e "s/username_here/wp_app/" \
  -e "s#password_here#$WP_PW#" \
  -e "s/localhost/$SQLHOST/" \
  /var/www/html/wp-config.php
chown -R www-data:www-data /var/www/html

a2enmod rewrite
sed -i 's#<Directory /var/www/>#<Directory /var/www/>\n\tAllowOverride All#' /etc/apache2/apache2.conf
systemctl restart apache2
sleep 5

AP=$(aws secretsmanager get-secret-value --region ${region} --secret-id "${wp_admin_secret_arn}" --query SecretString --output text | jq -r .password)
curl -fsS -m 120 "http://localhost/wp-admin/install.php?step=2" \
  --data-urlencode "weblog_title=Contoso Blog" \
  --data-urlencode "user_name=admin" \
  --data-urlencode "admin_password=$AP" \
  --data-urlencode "admin_password2=$AP" \
  --data-urlencode "pw_weak=1" \
  --data-urlencode "admin_email=admin@contoso.example" \
  --data-urlencode "blog_public=1" \
  --data-urlencode "Submit=Install WordPress" \
  --data-urlencode "language=" -o /var/log/wp-install.html || echo "install POST returned non-zero"

IP=$(curl -fsS -H "X-aws-ec2-metadata-token: $(curl -fsS -X PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 60')" http://169.254.169.254/latest/meta-data/public-ipv4)
echo "project nami ready $(date -u +%FT%TZ) - http://$IP/  (admin / fbctf-sqlmod/wordpress-admin)"
