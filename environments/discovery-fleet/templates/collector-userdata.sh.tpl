#!/bin/bash
# Discovery node bootstrap. Logs to /var/log/user-data.log and the console.
set -uxo pipefail
exec > >(tee -a /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

# Self-destruct backstop — the launch template terminates on shutdown.
shutdown -h +${max_minutes} "discovery-fleet max lifetime reached"

dnf install -y iproute cronie
systemctl enable --now crond

# AWS Application Discovery Agent (Linux). Registration uses the instance
# profile (AWSApplicationDiscoveryAgentAccess); data lands in the account's
# Application Discovery Service home region.
cd /tmp
curl -fsSL -o aws-discovery-agent.tar.gz \
  "https://s3.${region}.amazonaws.com/aws-discovery-agent.${region}/linux/latest/aws-discovery-agent.tar.gz" \
  && tar -xzf aws-discovery-agent.tar.gz \
  && bash install -r "${region}" --force 2>&1 | tail -20 \
  || echo "WARN: agent install failed — see https://docs.aws.amazon.com/application-discovery/latest/userguide/setting-up-agent.html"

# Generate steady inter-node traffic so netstat-based dependency capture has
# real edges to report. Node 0 is the 'hub' the others poll.
cat >/usr/local/bin/fleet-chatter <<'CHATTER'
#!/bin/bash
PEERS="__PEERS__"
while true; do
  for p in $PEERS; do
    (echo "ping from $(hostname) $(date -u +%FT%TZ)" | timeout 2 bash -c "cat >/dev/tcp/$p/7") 2>/dev/null || true
    timeout 2 bash -c "cat </dev/tcp/$p/7" >/dev/null 2>&1 || true
  done
  sleep 15
done
CHATTER
sed -i "s|__PEERS__|${peer_ips}|" /usr/local/bin/fleet-chatter
chmod +x /usr/local/bin/fleet-chatter

# A tiny listener on :7 so peers have something to connect to.
cat >/etc/systemd/system/fleet-echo.service <<'UNIT'
[Unit]
Description=fleet echo listener
[Service]
ExecStart=/usr/bin/socat TCP-LISTEN:7,fork,reuseaddr SYSTEM:'cat'
Restart=always
[Install]
WantedBy=multi-user.target
UNIT
dnf install -y socat
systemctl enable --now fleet-echo.service

cat >/etc/systemd/system/fleet-chatter.service <<'UNIT'
[Unit]
Description=fleet chatter
After=network-online.target fleet-echo.service
[Service]
ExecStart=/usr/local/bin/fleet-chatter
Restart=always
[Install]
WantedBy=multi-user.target
UNIT
systemctl enable --now fleet-chatter.service

echo "discovery node ${node_index} ready $(date -u +%FT%TZ)"
