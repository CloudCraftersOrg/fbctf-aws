#!/bin/bash
# Builds the pinned fbctf source tarball and uploads the base artifact set
# (source, Node tarball, composer.phar, SQL files) to the artifacts bucket.
#
# The app source is CloudCraftersOrg/fbctf: facebookarchive/fbctf history with
# the five 2026 keep-alive patches applied as commits on top of upstream
# 4ec9b6b (NodeSource key, grunt pins, unison no-op, non-Secure session
# cookie, branding logo) — see that repo's log for the details. This script
# no longer patches anything; the git history is the source of truth.
#
# S3 keys keep the upstream-base name (fbctf-src-4ec9b6b-patched.tgz) so the
# deployed user-data templates stay stable.
set -euo pipefail

APP_REPO="${APP_REPO:-$HOME/Documents/CloudCrafters/fbctf}"   # clone of CloudCraftersOrg/fbctf
PATCHED_COMMIT="${PATCHED_COMMIT:-eba438b}"                    # pinned patched HEAD
UPSTREAM_BASE="4ec9b6b"                                        # naming only
BUCKET="${BUCKET:-fbctf-demo-artifacts-337058058699-use1}"
export AWS_PROFILE="${AWS_PROFILE:-cloudcrafters-sandbox}"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "[+] Exporting $PATCHED_COMMIT from $APP_REPO"
mkdir -p "$WORK/src"
git -C "$APP_REPO" archive "$PATCHED_COMMIT" | tar -x -C "$WORK/src"

echo "[+] Building tarball"
TARBALL="fbctf-src-${UPSTREAM_BASE}-patched.tgz"
tar czf "$WORK/$TARBALL" -C "$WORK/src" .

echo "[+] Fetching vendored downloads"
curl -sSL -o "$WORK/node-v6.17.1-linux-x64.tar.xz" https://nodejs.org/dist/v6.17.1/node-v6.17.1-linux-x64.tar.xz
curl -sSL https://nodejs.org/dist/v6.17.1/SHASUMS256.txt | grep linux-x64.tar.xz > "$WORK/node.sha"
(cd "$WORK" && shasum -a 256 -c node.sha)
curl -sSL -o "$WORK/composer-2.2.29.phar" https://getcomposer.org/download/2.2.29/composer.phar

echo "[+] Uploading to s3://$BUCKET"
aws s3 cp "$WORK/$TARBALL" "s3://$BUCKET/source/$TARBALL" --no-progress
aws s3 cp "$WORK/node-v6.17.1-linux-x64.tar.xz" "s3://$BUCKET/vendored/node-v6.17.1-linux-x64.tar.xz" --no-progress
aws s3 cp "$WORK/composer-2.2.29.phar" "s3://$BUCKET/vendored/composer-2.2.29.phar" --no-progress
aws s3 cp "$APP_REPO/database/schema.sql" "s3://$BUCKET/sql/schema.sql" --no-progress
aws s3 cp "$APP_REPO/database/countries.sql" "s3://$BUCKET/sql/countries.sql" --no-progress
aws s3 cp "$APP_REPO/database/logos.sql" "s3://$BUCKET/sql/logos.sql" --no-progress
echo "[+] Done. Launch the builder (scripts/builder-userdata.sh) for the prebuilt tarball + HHVM debs."
