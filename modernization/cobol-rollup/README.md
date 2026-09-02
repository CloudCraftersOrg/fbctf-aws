# cobol-rollup — mainframe / COBOL modernization fixture

The nightly score-rollup batch on `finance-batch-01`: reads a fixed-width
capture file, aggregates per team, applies the disqualification rule, and writes
a ranked output file plus a control report. GnuCOBOL today; on a real mainframe
this would be COBOL + JCL.

```
src/ROLLUP.cbl          the program
copybooks/SCOREREC.cpy  input record layout (fixed-width, COMP-3)
copybooks/TEAMREC.cpy   output record layout
jcl/RUNROLL.sh          the "JCL" — DD assignments as env vars, run steps
data/scores.dat         sample input (10 capture records)
```

## Why this forces a real transformation

| Construct | What the agent must handle |
|---|---|
| `COMP-3` packed-decimal (TEAMREC output + working storage totals) | binary layout → typed numeric |
| `OCCURS 500 ... INDEXED BY` in-memory table | bounded array / collection with search |
| `PERFORM VARYING` + `SEARCH ALL` | loop + lookup idioms |
| `GO TO` inside `PERFORM ... THRU` paragraphs | structured control flow |
| Fixed-width `LINE SEQUENTIAL` / relative file I/O | streamed parsing / DB writes |
| `01`-level copybooks shared across programs | shared DTO / schema |
| Level-88 condition names | enums / predicates |
| SYSOUT control report with carriage control | structured log / report |

## Target

Java (Transform's mainframe target), invoked as a scheduled job for the spiky
nightly window on `finance-batch-01`. The COBOL is standalone — no CICS, no
DB2 — so it is a clean single-program conversion.
