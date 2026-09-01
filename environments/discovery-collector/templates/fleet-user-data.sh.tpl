#!/bin/bash
# Discovery target. The AWS Transform discovery tool SSHes in as ec2-user (key
# from key_name) and reads inventory / metrics / processes / netstat. Passwordless
# sudo is default on AL2023, which gives the tool full data (dmidecode, ss -p).
set -uxo pipefail
exec > >(tee -a /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

%{ if max_minutes > 0 ~}
shutdown -h +${max_minutes} "discovery target max lifetime"
%{ endif ~}
hostnamectl set-hostname ${hostname} || true

dnf install -y socat cronie || yum install -y socat cronie || true
if [ -f /etc/redhat-release ] || grep -qi 'amazon linux' /etc/os-release; then
  dnf install -y "https://dl.fedoraproject.org/pub/epel/epel-release-latest-9.noarch.rpm" || true
fi

case "${role}" in
  java8)
    dnf install -y java-1.8.0-amazon-corretto java-1.8.0-amazon-corretto-devel || true
    printf 'public class Svc{public static void main(String[] a)throws Exception{while(true)Thread.sleep(60000);}}' >/tmp/Svc.java
    (cd /tmp && javac Svc.java && nohup java Svc >/dev/null 2>&1 &) || true
    ;;
  cobol)
    dnf install -y gnucobol || true
    printf '       IDENTIFICATION DIVISION.\n       PROGRAM-ID. rollup.\n       PROCEDURE DIVISION.\n           PERFORM UNTIL 1 = 2\n               CALL "C$SLEEP" USING 30\n           END-PERFORM.\n           STOP RUN.\n' >/tmp/rollup.cob
    (cd /tmp && cobc -x -free -o rollup rollup.cob && nohup cobcrun ./rollup >/dev/null 2>&1 &) || true
    ;;
  redis)
    dnf install -y redis6 || dnf install -y redis || true
    systemctl enable --now redis6 || systemctl enable --now redis || nohup redis-server --port 6379 &
    ;;
  rabbitmq)
    dnf install -y rabbitmq-server || true
    systemctl enable --now rabbitmq-server || true
    ;;
  nfs)
    dnf install -y nfs-utils || true
    mkdir -p /srv/batch && echo "/srv/batch 10.70.0.0/16(ro,sync,no_subtree_check)" >>/etc/exports
    systemctl enable --now nfs-server || true
    exportfs -ra || true
    ;;
  jenkins)
    dnf install -y java-17-amazon-corretto || true
    curl -fsSL -o /opt/jenkins.war https://get.jenkins.io/war-stable/2.462.3/jenkins.war || true
    nohup java -jar /opt/jenkins.war --httpPort=8080 >/dev/null 2>&1 &
    ;;
esac

# Listener + chatter so the discovery tool's netstat sees real ESTABLISHED edges.
nohup socat TCP-LISTEN:7,fork,reuseaddr SYSTEM:'cat' >/dev/null 2>&1 &
cat >/usr/local/bin/estate-chatter <<'CHAT'
#!/bin/bash
while true; do
  for p in ${peer_ips}; do
    timeout 3 bash -c "echo x >/dev/tcp/$p/7" 2>/dev/null || true
  done
  sleep 20
done
CHAT
chmod +x /usr/local/bin/estate-chatter
cat >/etc/systemd/system/estate-chatter.service <<'UNIT'
[Unit]
After=network-online.target
[Service]
ExecStart=/usr/local/bin/estate-chatter
Restart=always
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload && systemctl enable --now estate-chatter.service

echo "discovery target ${hostname} (${role}) ready $(date -u +%FT%TZ)"
