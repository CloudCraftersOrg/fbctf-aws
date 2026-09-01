# Contoso Scoreboard — live .NET Framework app

A deliberately old-fashioned web app so the migration assessment has a real
**Windows Server + IIS + .NET Framework 4.8 + SQL Server** workload, and the
SQL Server → Aurora job (feature 10a) has an application data layer to rewrite,
not just a schema.

| File | What |
|---|---|
| `Default.aspx` | ASP.NET **Web Forms** page, C# in `<script runat="server">` — leaderboard grid + forms that call the stored procs via inline `System.Data.SqlClient` |
| `web.config` | `<connectionStrings>` (the instance user-data substitutes `__CONNSTRING__`), `<system.web><compilation targetFramework="4.8">` |

## Migration blockers it exhibits

| Construct | Transform must |
|---|---|
| ASP.NET Web Forms | no .NET Core successor — port to Razor Pages / MVC |
| `System.Data.SqlClient` | → `Microsoft.Data.SqlClient` |
| inline `SqlCommand` on `usp_*` procs | procs convert to PL/pgSQL; calls rewrite for Npgsql |
| `<connectionStrings>` in `web.config` | → `appsettings.json` + options |
| runtime page compilation, `HttpContext` | → build-time compile, DI-scoped context |

## Deploy

`environments/sqlmod` with `deploy_app = true` (default). Source is staged to the
schema S3 bucket under `app/` and pulled to `C:\inetpub\wwwroot` at boot; the
box also creates the `scoreboard_app` SQL login (the app never connects as `sa`).
`terraform output app_url`.
