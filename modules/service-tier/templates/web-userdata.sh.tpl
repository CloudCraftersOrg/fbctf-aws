#!/bin/bash
# fbctf web tier (nginx) boot provisioning. Strategy (requirements §3.3):
#   1. prebuilt tarball from S3
#   2. the app's own provision.sh (-m prod -R, multi-server nginx) — exercises
#      the patched NodeSource repo, the pinned grunt, and the unison no-op;
#      wires fastcgi_pass to the internal NLB via --hhvm-server
#   3. replace the generated TLS site config with an HTTP-only version of the
#      same server block: TLS terminates at the ALB (§1); the app's own :80
#      block is only a 301-to-https, which would loop behind an HTTP-only ALB
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
apt-get install -y curl unzip jq ca-certificates apt-transport-https software-properties-common
curl -sSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/awscli.zip
unzip -q /tmp/awscli.zip -d /tmp && /tmp/aws/install

param() { aws ssm get-parameter --name "/fbctf/$1" --query Parameter.Value --output text --region "$REGION"; }
NLB_DNS=$(param nlb_dns)

# --- prebuilt app tarball ---
mkdir -p /root/fbctf
aws s3 cp "s3://$BUCKET/$PREBUILT_KEY" /tmp/app.tgz --region "$REGION"
tar xzf /tmp/app.tgz -C /root/fbctf

# --- the app's own provisioning (nginx server type) ---
cd /root/fbctf
./extra/provision.sh -m prod -R --multiple-servers --server-type nginx \
  --hhvm-server "$NLB_DNS" -s /root/fbctf -d "$CTF_PATH"

# --- HTTP-only site config (TLS terminates at the ALB) ---
# Same locations/fastcgi wiring as the app's extra/nginx/nginx.conf, minus the
# TLS server block and the :80→https redirect.
cat > /etc/nginx/sites-available/fbctf.conf <<NGINX
server_tokens off;

server {
  listen 80 default_server;

  add_header X-Frame-Options DENY;
  add_header X-Content-Type-Options nosniff;
  add_header Cache-Control "no-cache, no-store";
  add_header Pragma "no-cache";
  expires -1;

  root $CTF_PATH/src;
  index index.php;

  location /data/customlogos/ {
    fastcgi_intercept_errors on;
    fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    include fastcgi_params;
    fastcgi_pass $NLB_DNS:9000;
  }

  location ~ \.php\$ {
    try_files \$uri =404;
    fastcgi_pass $NLB_DNS:9000;
    fastcgi_intercept_errors on;
    fastcgi_index index.php;
    fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
    include fastcgi_params;
  }
  error_page 400 401 402 403 404 500 /error.php;
  client_max_body_size 25M;
}
NGINX
ln -sf /etc/nginx/sites-available/fbctf.conf /etc/nginx/sites-enabled/fbctf.conf
rm -f /etc/nginx/sites-enabled/default
nginx -t
service nginx restart

# --- verify locally before reporting healthy ---
sleep 2
curl -sf -o /dev/null http://localhost/static/css/fb-ctf.css
curl -s -o /tmp/index.html -w '%%{http_code}' http://localhost/index.php | grep -qE '200|302'

# --- CloudWatch agent (non-fatal: logging must never block the boot) ---
(
  set +e
  curl -sSL https://amazoncloudwatch-agent.s3.amazonaws.com/ubuntu/amd64/latest/amazon-cloudwatch-agent.deb -o /tmp/cwagent.deb
  dpkg -i /tmp/cwagent.deb
  cat > /opt/aws/amazon-cloudwatch-agent/etc/cw-config.json <<CFG
{"logs":{"logs_collected":{"files":{"collect_list":[
  {"file_path":"/var/log/nginx/error.log","log_group_name":"/fbctf/nginx","log_stream_name":"error-{instance_id}"},
  {"file_path":"/var/log/nginx/access.log","log_group_name":"/fbctf/nginx","log_stream_name":"access-{instance_id}"},
  {"file_path":"/var/log/user-data.log","log_group_name":"/fbctf/user-data","log_stream_name":"web-{instance_id}"}
]}}}}
CFG
  /opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
    -a fetch-config -m ec2 -s -c file:/opt/aws/amazon-cloudwatch-agent/etc/cw-config.json
) || echo "CloudWatch agent setup failed (non-fatal)"

echo "WEB TIER BOOT COMPLETE"
