#!/bin/bash
# fbctf artifact builder — runs as EC2 user-data on the Xenial AMI (Phase 2).
# Builds the pre-built app tarball (vendor/ + node_modules + grunt output) and
# captures the HHVM .deb set, then uploads everything to the artifacts bucket
# and shuts the instance down. Log: /var/log/builder.log (uploaded to S3 too).
set -euxo pipefail
exec > /var/log/builder.log 2>&1

BUCKET="fbctf-demo-artifacts-337058058699-use1"
SRC_KEY="source/fbctf-src-4ec9b6b-patched.tgz"
COMMIT="4ec9b6b"
export DEBIAN_FRONTEND=noninteractive
export HOME=/root

finish() {
  status=$?
  set +e
  aws s3 cp /var/log/builder.log "s3://${BUCKET}/build-status/builder.log" --region us-east-1
  if [ "$status" -eq 0 ]; then
    echo ok | aws s3 cp - "s3://${BUCKET}/build-status/DONE" --region us-east-1
  else
    echo "$status" | aws s3 cp - "s3://${BUCKET}/build-status/FAILED" --region us-east-1
  fi
  shutdown -h +1
}
trap finish EXIT

# --- prerequisites + AWS CLI v2 (Xenial glibc 2.23 satisfies the 2.17 floor) ---
apt-get update
apt-get install -y curl unzip ca-certificates apt-transport-https \
  software-properties-common xz-utils build-essential git rsync
curl -sSL https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip -o /tmp/awscli.zip
unzip -q /tmp/awscli.zip -d /tmp && /tmp/aws/install
aws --version

# --- fetch patched source ---
mkdir -p /opt/fbctf
aws s3 cp "s3://${BUCKET}/${SRC_KEY}" /tmp/src.tgz --region us-east-1
tar xzf /tmp/src.tgz -C /opt/fbctf

# --- HHVM 3.21 (capture the .debs while installing) ---
apt-key adv --recv-keys --keyserver hkp://keyserver.ubuntu.com:80 0x5a16e7281be7a449 || \
  curl -sSL "http://keyserver.ubuntu.com/pks/lookup?op=get&search=0x5a16e7281be7a449" | apt-key add -
apt-key adv --recv-keys --keyserver hkp://keyserver.ubuntu.com:80 0xB4112585D386EB94 || \
  curl -sSL "http://keyserver.ubuntu.com/pks/lookup?op=get&search=0xB4112585D386EB94" | apt-key add -
add-apt-repository "deb http://dl.hhvm.com/ubuntu xenial-lts-3.21 main"
apt-get update
apt-get clean
apt-get install -y hhvm
hhvm --version
mkdir -p /opt/hhvm-debs
cp /var/cache/apt/archives/*.deb /opt/hhvm-debs/

# --- composer install (vendor/) ---
aws s3 cp "s3://${BUCKET}/vendored/composer-2.2.29.phar" /usr/local/bin/composer.phar --region us-east-1
cd /opt/fbctf
hhvm /usr/local/bin/composer.phar install --no-interaction
test -d vendor

# --- Node 6 + npm install + grunt build ---
aws s3 cp "s3://${BUCKET}/vendored/node-v6.17.1-linux-x64.tar.xz" /tmp/node.tar.xz --region us-east-1
tar xJf /tmp/node.tar.xz -C /usr/local --strip-components=1
node --version && npm --version
npm install --unsafe-perm
./node_modules/.bin/grunt --force
test -f src/static/build/app-browserify.js

# --- package + upload ---
cd /opt
tar czf "fbctf-prebuilt-${COMMIT}.tgz" -C fbctf .
tar czf hhvm-debs-xenial-3.21.tgz -C hhvm-debs .
sha256sum "fbctf-prebuilt-${COMMIT}.tgz" hhvm-debs-xenial-3.21.tgz > builder-checksums.txt
aws s3 cp "fbctf-prebuilt-${COMMIT}.tgz" "s3://${BUCKET}/prebuilt/fbctf-prebuilt-${COMMIT}.tgz" --region us-east-1
aws s3 cp hhvm-debs-xenial-3.21.tgz "s3://${BUCKET}/vendored/hhvm-debs-xenial-3.21.tgz" --region us-east-1
aws s3 cp builder-checksums.txt "s3://${BUCKET}/build-status/builder-checksums.txt" --region us-east-1
echo "BUILD COMPLETE"
