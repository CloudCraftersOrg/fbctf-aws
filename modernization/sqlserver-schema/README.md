# sqlserver-schema — SQL Server → Aurora schema conversion fixture

The `Scoreboard` database on `contoso-sql-01` (SQL Server 2017 Standard). This
is the database that **routes** in a Transform assessment — the live fbctf app's
MySQL returned "no compatible routing target"; SQL Server converts to Aurora
PostgreSQL / MySQL.

```
01_tables.sql          tables, keys, an IDENTITY, a SEQUENCE, a computed column
02_programmability.sql  procedures, a scalar UDF, a trigger, a view with TOP + a cursor
03_seed.sql             minimal reference data
```

## Why this forces manual-review conversion items

| T-SQL construct | Where | Conversion note the agent raises |
|---|---|---|
| `MERGE` | `usp_UpsertTeam` | PostgreSQL: `INSERT ... ON CONFLICT`; MySQL: `INSERT ... ON DUPLICATE KEY` |
| `IDENTITY(1,1)` + `SCOPE_IDENTITY()` | `Teams`, `usp_RecordCapture` | serial / `AUTO_INCREMENT` + `RETURNING` / `LAST_INSERT_ID()` |
| `SEQUENCE` + `NEXT VALUE FOR` | `EventSeq` | native sequence (PG) / emulation (MySQL) |
| scalar UDF in a computed column | `Teams.RankBucket` → `dbo.fn_RankBucket` | inline expression or generated column |
| `AFTER INSERT` trigger with `inserted` | `trg_Captures_Audit` | row trigger + `NEW` |
| explicit `CURSOR` / `FETCH NEXT` | `usp_RecalculateRanks` | set-based rewrite or `FOR` loop |
| `TOP (n) WITH TIES` | `vw_Leaderboard` | `LIMIT` + window function |
| `GETUTCDATE()`, `DATEADD`, `DATEDIFF` | throughout | `now() at time zone 'utc'`, interval arithmetic |
| `NVARCHAR`, `BIT`, `DATETIME2` | `01_tables.sql` | type mapping |

## Target

Aurora PostgreSQL 15 for `contoso-sql-01`, with `contoso-sql-rpt-01` collapsing
into an Aurora reader endpoint (see the inventory).
