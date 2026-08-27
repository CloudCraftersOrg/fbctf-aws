# Artifacts manifest — s3://fbctf-demo-artifacts-337058058699-use1

Built 2026-08-27 (rev 2: patch 4 added during Phase 6). Source pinned to fbctf
commit `4ec9b6b` with the four validated patches (NodeSource `trusted=yes`,
local grunt 1.0.4 pin, unison no-op, GLOBAL grunt 1.0.4 pin + flow-bin drop in
provision.sh — see `scripts/make-source-tarball.sh`). Prebuilt tarball and HHVM
debs produced on a throwaway Xenial EC2 builder (`scripts/builder-userdata.sh`);
build log at `build-status/builder.log` in the bucket.

| Key | Size | SHA-256 |
|---|---|---|
| `source/fbctf-src-4ec9b6b-patched.tgz` | 15.0 MiB | `b05190e1a85b79dbfdb90a65912e31d8d8e899bbcccd21ad5f40da1ddc55fa96` |
| `prebuilt/fbctf-prebuilt-4ec9b6b.tgz` | 36.5 MiB | `88df4e0a6162518b9aa283b531961f8c06daa4943564f789f8651e565947544c` |
| `vendored/hhvm-debs-xenial-3.21.tgz` | 31.4 MiB | `efc8b91b21a249e0a17c45ed1a589c076dd48e2dbc7a4bafcdc8b40f165e7cf5` |
| `vendored/node-v6.17.1-linux-x64.tar.xz` | 9.0 MiB | `0f88dacefc4be4709e0a9f9fe685efdfe1582a724d8f42614179c2f604c36165` (matches nodejs.org SHASUMS256.txt) |
| `vendored/composer-2.2.29.phar` | 2.3 MiB | `f38623ebdeeab5905b24b048fd32804150e598436cc43db9fc12362894c1279d` |
| `sql/schema.sql` | 19.3 KiB | from repo commit 4ec9b6b |
| `sql/countries.sql` | 145.9 KiB | from repo commit 4ec9b6b |
| `sql/logos.sql` | 22.7 KiB | from repo commit 4ec9b6b |

The prebuilt tarball contains the full app tree with `vendor/` (Composer 2.2.29
under HHVM 3.21.11), `node_modules/` (Node 6.17.1 / npm 3.10.10), and the grunt
build output (`src/static/build/app-browserify.js` verified present). App-tier
boot only needs: HHVM install (dl.hhvm.com or the vendored debs) + untar this +
render settings.ini + DB bootstrap.
