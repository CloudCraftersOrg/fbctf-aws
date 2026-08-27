# ADR 003 — RDS MySQL 8.0 with mysql_native_password

**Status:** Accepted (2026-08-26)

## Context
The app was built against MySQL 5.7-era servers. RDS MySQL 5.7 is past EOL (extended-support cost). Validated 2026-08-26 against mysql:8.0.46: `schema.sql` + `countries.sql` + `logos.sql` import cleanly under **stock strict** `sql_mode` (all tables InnoDB/latin1, no zero-date defaults, no reserved-word conflicts). The one real 8.0 incompatibility is authentication: HHVM 3.21's 2017-era MySQL client cannot speak `caching_sha2_password`, MySQL 8's default — the classic "imports fine, app can't connect" failure.

## Decision
RDS MySQL 8.0. The app DB user is created `IDENTIFIED WITH mysql_native_password` (validated working). The parameter group relaxes `sql_mode` to `NO_ENGINE_SUBSTITUTION` as a precaution for 2018-era runtime queries — the import itself needed none. Note: `default_authentication_plugin` turned out to be immutable on RDS MySQL 8.0 — and already defaults to `mysql_native_password` there (verified live 2026-08-27), so no parameter is set for it.

## Consequences
- No extended-support fees; no EOL engine.
- DB bootstrap (schema import, app user, admin row) is owned by app-tier user-data behind a one-shot guard (`SELECT 1 FROM configuration LIMIT 1` — seeded by schema.sql, flips exactly once), because with RDS nothing ever runs provision's `--server-type mysql` path.
- Runtime queries are untested against 8.0 until Phase 5/6 — relaxed sql_mode is the safety net.
