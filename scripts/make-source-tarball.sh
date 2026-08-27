#!/bin/bash
# Builds the pinned+patched fbctf source tarball and uploads the base artifact
# set (source, Node tarball, composer.phar, SQL files) to the artifacts bucket.
# Run from anywhere; requires a clone of facebookarchive/fbctf and AWS creds.
#
# The three patches applied here were validated live on 2026-08-26 (see
# fbctf-aws-requirements.md §3.3 and ADR 001):
#   1. extra/lib.sh install_unison  -> no-op (upstream Arch URL now serves zstd)
#   2. extra/lib.sh install_nodejs  -> NodeSource repo with trusted=yes
#   3. package.json                 -> pin grunt to 1.0.4
set -euo pipefail

FBCTF_REPO="${FBCTF_REPO:-$HOME/Documents/CloudCrafters/fbctf}"
COMMIT="${COMMIT:-4ec9b6b}"
BUCKET="${BUCKET:-fbctf-demo-artifacts-337058058699-use1}"
export AWS_PROFILE="${AWS_PROFILE:-cloudcrafters-sandbox}"

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

echo "[+] Exporting $COMMIT from $FBCTF_REPO"
mkdir -p "$WORK/src"
git -C "$FBCTF_REPO" archive "$COMMIT" | tar -x -C "$WORK/src"

echo "[+] Applying patches"
python3 - "$WORK/src" <<'EOF'
import pathlib, sys
root = pathlib.Path(sys.argv[1])

lib = root / "extra/lib.sh"
s = lib.read_text()
old_unison = '''function install_unison() {
  cd /
  dl_pipe "https://www.archlinux.org/packages/extra/x86_64/unison/download/" | sudo tar Jx
}'''
new_unison = '''function install_unison() {
  # fbctf-aws patch: upstream Arch package is now zstd-compressed and "tar Jx"
  # dies under set -e. Unison is a dev-only file sync tool — skip it.
  log "Skipping unison install (fbctf-aws patch)"
}'''
assert old_unison in s, "unison block not found"
s = s.replace(old_unison, new_unison)

old_node = '''function install_nodejs() {
  log "Downloading and setting node.js version 6.x repo information"
  dl_pipe "https://deb.nodesource.com/setup_6.x" | sudo -E bash -

  log "Installing node.js"
  package nodejs
}'''
new_node = '''function install_nodejs() {
  # fbctf-aws patch: NodeSource re-signed their repos in 2023; the setup_6.x
  # script installs a key that no longer verifies and apt refuses nodejs.
  # Pin the repo entry directly with trusted=yes (and skip the setup script's
  # 80 seconds of deprecation-warning sleeps).
  log "Adding NodeSource node 6.x repo (fbctf-aws patch: trusted=yes)"
  package apt-transport-https
  echo "deb [trusted=yes] https://deb.nodesource.com/node_6.x xenial main" | sudo tee /etc/apt/sources.list.d/nodesource.list
  package_repo_update

  log "Installing node.js"
  package nodejs
}'''
assert old_node in s, "nodejs block not found"
s = s.replace(old_node, new_node)
lib.write_text(s)

pkg = root / "package.json"
s = pkg.read_text()
assert '"grunt": "^1.0.1"' in s
pkg.write_text(s.replace('"grunt": "^1.0.1"', '"grunt": "1.0.4"'))

# Patch 4: provision.sh installs GLOBAL grunt unpinned — npm resolves 1.6.x,
# whose dependencies use syntax Node 6 cannot parse, and provision dies under
# set -e. Pin it; skip flow-bin (dev-only type checker, latest also breaks).
prov = root / "extra/provision.sh"
s = prov.read_text()
old = '''        sudo npm install -g grunt
        sudo npm install -g flow-bin'''
new = '''        # fbctf-aws patch: pin global grunt (unpinned resolves to 1.6.x, which
        # Node 6 cannot parse); skip flow-bin (dev-only, latest breaks on Node 6)
        sudo npm install -g grunt@1.0.4'''
assert old in s, "global npm install block not found"
prov.write_text(s.replace(old, new))

# Patch 5: the session cookie is hardcoded Secure — built for the original
# HTTPS-only nginx. Served over the HTTP-only ALB, browsers drop the cookie
# and every login silently bounces back to the login page.
sess = root / "src/SessionUtils.php"
s = sess.read_text()
old = "private static bool $s_secure = true;"
new = ("// fbctf-aws patch: TLS terminates at the ALB and the app is served\n"
       "  // over plain HTTP — a Secure cookie would never be sent back.\n"
       "  private static bool $s_secure = false;")
assert old in s, "s_secure not found"
sess.write_text(s.replace(old, new))
print("[+] all 5 patches applied")
EOF

echo "[+] Injecting demo branding logo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp "$SCRIPT_DIR/../assets/custom-branding.png" "$WORK/src/src/static/img/custom-branding.png"

echo "[+] Building tarball"
TARBALL="fbctf-src-${COMMIT}-patched.tgz"
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
aws s3 cp "$FBCTF_REPO/database/schema.sql" "s3://$BUCKET/sql/schema.sql" --no-progress
aws s3 cp "$FBCTF_REPO/database/countries.sql" "s3://$BUCKET/sql/countries.sql" --no-progress
aws s3 cp "$FBCTF_REPO/database/logos.sql" "s3://$BUCKET/sql/logos.sql" --no-progress
echo "[+] Done. Launch the builder (scripts/builder-userdata.sh) for the prebuilt tarball + HHVM debs."
