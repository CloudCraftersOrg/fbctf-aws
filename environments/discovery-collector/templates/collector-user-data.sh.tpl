#!/bin/bash
# Installs the AWS Transform discovery tool (Linux installer) and stages the
# import CSV + SSH key. You then open the UI (SSM port-forward :5000), add the
# key as an OS credential, add the CSV as a "Server import" source, and let it
# collect. Logs: /var/log/user-data.log and `discovery-tool logs`.
set -uxo pipefail
exec > >(tee -a /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

%{ if max_minutes > 0 ~}
shutdown -h +${max_minutes} "discovery collector max lifetime"
%{ endif ~}

mkdir -p /opt/discovery
cat >/opt/discovery/fbctf-discovery.pem <<'PEM'
${ssh_key_pem}
PEM
chmod 600 /opt/discovery/fbctf-discovery.pem

cat >/opt/discovery/import.csv <<'CSV'
${import_csv}
CSV

cd /opt/discovery
curl -fsSL -O https://s3.us-east-1.amazonaws.com/atx.discovery.collector.bundle/releases/latest/AWS-Transform-discovery-tool.sh
chmod +x AWS-Transform-discovery-tool.sh
chown -R ec2-user:ec2-user /opt/discovery

# The installer resolves its data dir from the invoking user's home and refuses
# to run for root. user-data is root, so run it as ec2-user via sudo (sets
# SUDO_USER); ec2-user has passwordless sudo on AL2023.
runuser -l ec2-user -c 'cd /opt/discovery && sudo ./AWS-Transform-discovery-tool.sh check' || true
runuser -l ec2-user -c 'cd /opt/discovery && sudo ./AWS-Transform-discovery-tool.sh install --install-deps'
runuser -l ec2-user -c 'cd /opt/discovery && sudo ./AWS-Transform-discovery-tool.sh start'
sleep 5
systemctl is-active discovery-tool || true

IP=$(curl -fsS -H "X-aws-ec2-metadata-token: $(curl -fsS -X PUT http://169.254.169.254/latest/api/token -H 'X-aws-ec2-metadata-token-ttl-seconds: 60')" http://169.254.169.254/latest/meta-data/local-ipv4)
echo "discovery tool ready — UI at https://$IP:5000"
echo "  SSH key : /opt/discovery/fbctf-discovery.pem   (user: ec2-user for the fleet + AL2023 hosts, ubuntu for Project Nami)"
echo "  import  : /opt/discovery/import.csv"
