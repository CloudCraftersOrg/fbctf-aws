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

SITE="${site_url}"
cp /var/www/html/wp-config-sample.php /var/www/html/wp-config.php
sed -i \
  -e "s/database_name_here/wordpress/" \
  -e "s/username_here/wp_app/" \
  -e "s#password_here#$WP_PW#" \
  -e "s/localhost/$SQLHOST/" \
  /var/www/html/wp-config.php
# pin the URL so the browser never sees a localhost asset/link
sed -i "s#/\* That's all, stop editing.*#define('WP_HOME','$SITE');\ndefine('WP_SITEURL','$SITE');\n&#" /var/www/html/wp-config.php
chown -R www-data:www-data /var/www/html

a2enmod rewrite
sed -i '/<Directory \/var\/www\/>/,/<\/Directory>/ s/AllowOverride None/AllowOverride All/' /etc/apache2/apache2.conf
cat > /var/www/html/.htaccess <<'HT'
# BEGIN WordPress
<IfModule mod_rewrite.c>
RewriteEngine On
RewriteBase /
RewriteRule ^index\.php$ - [L]
RewriteCond %%{REQUEST_FILENAME} !-f
RewriteCond %%{REQUEST_FILENAME} !-d
RewriteRule . /index.php [L]
</IfModule>
# END WordPress
HT
chown www-data:www-data /var/www/html/.htaccess
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

TT5=/var/www/html/wp-content/themes/twentytwentyfive/parts
cat > $TT5/header.html <<'HDR'
<!-- wp:group {"tagName":"header","align":"full","style":{"spacing":{"padding":{"top":"1rem","bottom":"1rem"}}},"layout":{"type":"constrained"}} -->
<header class="wp-block-group alignfull" style="padding-top:1rem;padding-bottom:1rem">
<!-- wp:group {"align":"wide","layout":{"type":"flex","justifyContent":"space-between","flexWrap":"nowrap"}} -->
<div class="wp-block-group alignwide">
<!-- wp:site-title {"level":1} /-->
<!-- wp:navigation {"ref":4,"overlayMenu":"mobile","layout":{"type":"flex","justifyContent":"right"}} /-->
</div>
<!-- /wp:group -->
</header>
<!-- /wp:group -->
HDR
cat > $TT5/footer.html <<'FT'
<!-- wp:group {"tagName":"footer","align":"full","style":{"spacing":{"padding":{"top":"2rem","bottom":"2rem"}}},"layout":{"type":"constrained"}} -->
<footer class="wp-block-group alignfull" style="padding-top:2rem;padding-bottom:2rem">
<!-- wp:paragraph {"fontSize":"small"} --><p class="has-small-font-size"><strong>Contoso Blog</strong> &mdash; Project Nami on SQL Server</p><!-- /wp:paragraph -->
</footer>
<!-- /wp:group -->
FT
chown -R www-data:www-data $TT5

pnq() { "$SQLCMD" -S "$SQLHOST,1433" -U sa -P "$SA_PW" -C -b -d wordpress -Q "$1"; }
pnq "UPDATE wp_options SET option_value='$SITE' WHERE option_name IN ('siteurl','home');
     UPDATE wp_options SET option_value='/%postname%/' WHERE option_name='permalink_structure';
     UPDATE wp_options SET option_value='Contoso migration blog - a Project Nami (WordPress on SQL Server) demo' WHERE option_name='blogdescription';
     DELETE FROM wp_options WHERE option_name LIKE '%transient%' OR option_name='rewrite_rules';
     UPDATE wp_posts SET post_content='<!-- wp:navigation-link {\"label\":\"Home\",\"url\":\"/\",\"kind\":\"custom\"} /--><!-- wp:navigation-link {\"label\":\"About\",\"url\":\"/about/\",\"kind\":\"custom\"} /-->' WHERE post_type='wp_navigation';
     UPDATE wp_posts SET post_title='About', post_name='about', post_status='publish',
       post_content='<!-- wp:paragraph --><p>Contoso is migrating a portfolio of legacy workloads to AWS with AWS Transform. This blog runs on Project Nami - WordPress on SQL Server - one of the apps in that portfolio.</p><!-- /wp:paragraph -->'
       WHERE post_type='page';
     UPDATE wp_posts SET post_title='Welcome to the Contoso migration blog',
       post_content='<!-- wp:paragraph --><p>We are moving Contoso off self-managed databases. Follow along as the .NET, PHP and Java apps get assessed and modernized.</p><!-- /wp:paragraph -->'
       WHERE post_type='post' AND post_name='hello-world';"
for slug_title in "assessing-the-sql-server-estate:::Assessing the SQL Server estate:::AWS Transform inventoried the Windows + IIS + SQL Server hosts over WinRM and flagged the schema objects that need conversion." \
                  "wordpress-on-sql-server:::WordPress on SQL Server:::Project Nami swaps the WordPress MySQL layer for pdo_sqlsrv so the same content model runs on SQL Server."; do
  s=$${slug_title%%:::*}; rest=$${slug_title#*:::}; t=$${rest%%:::*}; b=$${rest#*:::}
  pnq "IF NOT EXISTS (SELECT 1 FROM wp_posts WHERE post_name='$s')
       INSERT INTO wp_posts (post_author,post_date,post_date_gmt,post_content,post_title,post_status,comment_status,ping_status,post_name,post_modified,post_modified_gmt,post_type,post_excerpt,to_ping,pinged,post_content_filtered)
       VALUES (1,SYSDATETIME(),SYSUTCDATETIME(),'<!-- wp:paragraph --><p>$b</p><!-- /wp:paragraph -->','$t','publish','open','open','$s',SYSDATETIME(),SYSUTCDATETIME(),'post','','','','');"
done

php -r 'opcache_reset();' 2>/dev/null || true
systemctl restart apache2

# Hold a pdo_sqlsrv connection open + keep the site warm, so the discovery tool's
# netstat sweep records the PHP-app -> SQL Server dependency edge.
cat >/usr/local/bin/wp-warm.php <<'PHP'
<?php
while (true) {
  try {
    $db = new PDO("sqlsrv:Server=SQLHOST,1433;Database=wordpress;TrustServerCertificate=true", "wp_app", getenv("WPPW"));
    while (true) { $db->query("SELECT 1")->fetch(); sleep(15); }
  } catch (Exception $e) { sleep(10); }
}
PHP
sed -i "s/SQLHOST/$SQLHOST/" /usr/local/bin/wp-warm.php
cat >/etc/systemd/system/wp-warm.service <<UNIT
[Unit]
Description=Project Nami DB warm (discovery)
After=network-online.target
[Service]
Environment=WPPW=$WP_PW
ExecStart=/usr/bin/php /usr/local/bin/wp-warm.php
Restart=always
[Install]
WantedBy=multi-user.target
UNIT
cat >/etc/systemd/system/wp-http-warm.service <<'UNIT'
[Unit]
Description=Project Nami HTTP warm (discovery)
[Service]
ExecStart=/bin/bash -c 'while true; do curl -s -o /dev/null http://localhost/ ; sleep 5; done'
Restart=always
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload
systemctl enable --now wp-warm.service wp-http-warm.service

echo "project nami ready $(date -u +%FT%TZ) - $SITE/  (admin / fbctf-sqlmod/wordpress-admin)"
