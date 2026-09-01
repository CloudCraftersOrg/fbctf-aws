#!/bin/bash
# Estate host bootstrap (Linux). Best-effort: installs the role runtime, starts
# a process under the name the assessment keys on, and generates the dependency
# edges. Logs to /var/log/user-data.log; reach the host with SSM.
set -uxo pipefail
exec > >(tee -a /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

shutdown -h +${max_minutes} "estate host max lifetime reached"

hostnamectl set-hostname ${hostname}.corp.local || hostname ${hostname}

%{ for name, ip in hosts_map ~}
grep -q " ${name}$" /etc/hosts || echo "${ip} ${name}.corp.local ${name}" >> /etc/hosts
%{ endfor ~}

# ---- package manager shim (apt on Xenial, yum/dnf elsewhere) --------------
if command -v apt-get >/dev/null; then
  export DEBIAN_FRONTEND=noninteractive
  PKG="apt-get install -y"
  apt-get update -y || true
elif command -v dnf >/dev/null; then
  PKG="dnf install -y"
else
  PKG="yum install -y"
fi

# EPEL / extras for packages missing from the base repos (socat on RHEL,
# redis on Amazon Linux 2, gnucobol).
if command -v amazon-linux-extras >/dev/null; then
  amazon-linux-extras install -y epel || true
elif [ -f /etc/redhat-release ]; then
  $PKG "https://dl.fedoraproject.org/pub/epel/epel-release-latest-$(rpm -E %rhel).noarch.rpm" || true
fi
$PKG socat curl || $PKG socat || true

# SSM agent is not preinstalled on RHEL or Ubuntu 16.04.
if ! pgrep -f amazon-ssm-agent >/dev/null; then
  if [ -f /etc/redhat-release ]; then
    $PKG "https://s3.${region}.amazonaws.com/amazon-ssm-${region}/latest/linux_amd64/amazon-ssm-agent.rpm" || true
  elif command -v snap >/dev/null; then
    snap install amazon-ssm-agent --classic || true
  else
    curl -fsSL -o /tmp/ssm.deb "https://s3.${region}.amazonaws.com/amazon-ssm-${region}/latest/debian_amd64/amazon-ssm-agent.deb" && dpkg -i /tmp/ssm.deb || true
  fi
  systemctl enable --now amazon-ssm-agent 2>/dev/null \
    || systemctl enable --now snap.amazon-ssm-agent.amazon-ssm-agent 2>/dev/null || true
fi

# ---- role runtime --------------------------------------------------------
case "${role}" in
  java8)
    $PKG java-1.8.0-openjdk-devel || $PKG openjdk-8-jdk || $PKG java-1.8.0-openjdk || true
    cat >/tmp/Svc.java <<'J'
public class Svc { public static void main(String[] a) throws Exception {
  while (true) { Thread.sleep(60000); } } }
J
    (cd /tmp && javac Svc.java && nohup java Svc >/dev/null 2>&1 &) || true
    ;;
  cobol)
    $PKG gnucobol || $PKG gnucobol4 || $PKG open-cobol || true
    cat >/tmp/rollup.cob <<'C'
       IDENTIFICATION DIVISION.
       PROGRAM-ID. rollup.
       PROCEDURE DIVISION.
           PERFORM UNTIL 1 = 2
               CALL "C$SLEEP" USING 30
           END-PERFORM.
           STOP RUN.
C
    (cd /tmp && cobc -x -free -o rollup rollup.cob && nohup cobcrun ./rollup >/dev/null 2>&1 &) \
      || (cd /tmp && cobc -x -free -o rollup rollup.cob && nohup ./rollup >/dev/null 2>&1 &) || true
    ;;
  redis)
    amazon-linux-extras install -y redis6 || $PKG redis || $PKG redis-server || true
    systemctl enable --now redis6 || systemctl enable --now redis \
      || systemctl enable --now redis-server || nohup redis-server --port 6379 &
    ;;
  rabbitmq)
    $PKG rabbitmq-server || true
    systemctl enable --now rabbitmq-server || nohup rabbitmq-server &
    ;;
  nfs)
    $PKG nfs-utils || $PKG nfs-kernel-server || true
    mkdir -p /srv/batch && echo "/srv/batch 10.30.0.0/16(ro,sync,no_subtree_check)" >> /etc/exports
    systemctl enable --now nfs-server || systemctl enable --now nfs-kernel-server || true
    exportfs -ra || true
    ;;
  jenkins)
    $PKG java-11-amazon-corretto || $PKG java-11-openjdk || $PKG openjdk-11-jdk || true
    # 2.462.3 is the last line that still runs on Java 11.
    curl -fsSL -o /opt/jenkins.war https://get.jenkins.io/war-stable/2.462.3/jenkins.war || true
    nohup java -jar /opt/jenkins.war --httpPort=8080 >/dev/null 2>&1 &
    ;;
esac

# ---- inbound listeners for the edges that terminate here ------------------
# Only where the role service isn't already bound (redis/rabbitmq/nfs/sqlservr
# own their port; the rest get a stub so the connection establishes).
sleep 5
%{ for p in listen_ports ~}
ss -ltn 2>/dev/null | grep -q ":${p} " || nohup socat TCP-LISTEN:${p},fork,reuseaddr SYSTEM:'cat' >/dev/null 2>&1 &
%{ endfor ~}

# ---- chatter: generate the outbound edges from this host -----------------
cat >/usr/local/bin/estate-chatter <<'CHAT'
#!/bin/bash
while true; do
%{ for t in chatter_targets ~}
  timeout 3 bash -c 'echo estate >/dev/tcp/${t.ip}/${t.port}' 2>/dev/null || true
%{ endfor ~}
  sleep 20
done
CHAT
chmod +x /usr/local/bin/estate-chatter
cat >/etc/systemd/system/estate-chatter.service <<'UNIT'
[Unit]
Description=estate chatter
After=network-online.target
[Service]
ExecStart=/usr/local/bin/estate-chatter
Restart=always
[Install]
WantedBy=multi-user.target
UNIT
systemctl daemon-reload && systemctl enable --now estate-chatter.service

%{ if install_agent ~}
cd /tmp
curl -fsSL -o ads.tar.gz "https://s3.${region}.amazonaws.com/aws-discovery-agent.${region}/linux/latest/aws-discovery-agent.tar.gz" \
  && tar -xzf ads.tar.gz && bash install -r "${region}" --force 2>&1 | tail -10 \
  || echo "WARN: discovery agent install failed"
%{ endif ~}

echo "estate host ${hostname} (${role}) ready $(date -u +%FT%TZ)"
