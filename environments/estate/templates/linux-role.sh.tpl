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
$PKG socat curl || $PKG socat || true

# ---- role runtime --------------------------------------------------------
case "${role}" in
  java8)
    $PKG java-1.8.0-openjdk || $PKG openjdk-8-jdk || $PKG java-1.8.0-openjdk-headless || true
    nohup java -version 2>/dev/null; nohup sleep infinity &
    # a long-lived JVM so the process shows as 'java'
    cat >/tmp/Svc.java <<'J'
public class Svc { public static void main(String[] a) throws Exception {
  while (true) { Thread.sleep(60000); } } }
J
    (cd /tmp && javac Svc.java && nohup java Svc &) || true
    ;;
  cobol)
    $PKG gnucobol || $PKG gnucobol4 || $PKG open-cobol || true
    cat >/tmp/loop.cob <<'C'
       IDENTIFICATION DIVISION.
       PROGRAM-ID. LOOP.
       PROCEDURE DIVISION.
       MAIN.
           PERFORM UNTIL 1 = 2
               CALL "C$SLEEP" USING 30
           END-PERFORM.
C
    (cd /tmp && cobc -m -free loop.cob 2>/dev/null && nohup cobcrun loop &) || \
      (cd /tmp && cobc -x -free -o loopx loop.cob 2>/dev/null && nohup ./loopx &) || true
    ;;
  redis)
    $PKG redis || $PKG redis-server || true
    systemctl enable --now redis || systemctl enable --now redis-server || \
      nohup redis-server --port 6379 &
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
    curl -fsSL -o /opt/jenkins.war https://get.jenkins.io/war-stable/latest/jenkins.war || true
    nohup java -jar /opt/jenkins.war --httpPort=8080 &
    ;;
esac

# ---- inbound listeners for the edges that terminate here ------------------
%{ for p in listen_ports ~}
nohup socat TCP-LISTEN:${p},fork,reuseaddr SYSTEM:'cat' >/dev/null 2>&1 &
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
