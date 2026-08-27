# ADR 001 — Boot-time provisioning instead of AMI baking

**Status:** Accepted (2026-08-26)

## Context
fbctf (archived 2018) targets Ubuntu 16.04 + HHVM 3.21. We can either bake AMIs (Packer) or let instances self-provision at boot via the repo's `provision.sh`. A live smoke test (2026-08-26, ubuntu:xenial container, amd64) confirmed all critical upstream sources still work: archive.ubuntu.com still serves Xenial, dl.hhvm.com serves `xenial-lts-3.21` (HHVM 3.21.11 installs and runs), getcomposer.org auto-selects Composer 2.2 LTS which runs under HHVM, and the repo's `composer.lock` resolves.

Four upstream breakages were found and have validated workarounds applied to the app tarball / user-data:
1. NodeSource re-signed its repos (2023) — old key fails; fix: `trusted=yes` source entry or Node 6.17.1 tarball from nodejs.org.
2. `package.json` has no lock file — `grunt ^1.0.1` floats to 1.6.x, which Node 6 cannot parse; fix: pin grunt 1.0.4.
3. `install_unison` pulls a rolling Arch Linux URL now served as zstd — `tar Jx` dies under `set -e`; fix: no-op (dev-only tool).
4. `dev` mode runs `pip install --upgrade pip` on Python 2 (breaks) — fix: always `-m prod -R`.

## Decision
No AMI baking for the demo. Instances self-provision at boot from a pinned, pre-patched app tarball in S3, with vendored packages (HHVM .debs, Node tarball, composer.phar) as insurance against upstream disappearing.

## Consequences
- ~15–20 min app-tier boot; ASG health check grace period must be generous.
- Boot depends on external repos (mitigated by S3 vendoring; NAT gateway required).
- The Ubuntu Xenial AMI itself is deprecated (2023) — the AMI data source needs `include_deprecated = true`; Canonical could remove it eventually. AMI baking is the #1 future hardening step.
