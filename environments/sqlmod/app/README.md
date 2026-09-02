# Contoso Scoreboard — the deployed .NET Framework app

This is the app **running on `fbctf-sqlmod-app`** (Windows Server 2022 + IIS,
`http://<eip>/`) — packaged as a buildable solution so it can go straight to
**AWS Transform** for .NET modernization.

| File | What it is |
|---|---|
| `ContosoScoreboard.sln` / `ContosoScoreboard.Web.csproj` | non-SDK Web Application Project, `net48` |
| `Default.aspx` | ASP.NET **Web Forms** page, C# inline in `<script runat="server">` — leaderboard grid + forms calling the SQL Server stored procs via `System.Data.SqlClient` |
| `Global.asax` / `Global.asax.cs` | `Application_Start` shell |
| `web.config` | `<connectionStrings>` (`__CONNSTRING__` substituted at boot), `<system.web><compilation targetFramework="4.8">` |
| `Dockerfile` | current-state **Windows container** (`dotnet/framework/aspnet:4.8`) |

## What Transform modernizes

Target: **Linux .NET 8 container**.

| Construct | → |
|---|---|
| ASP.NET Web Forms (`.aspx`, `<asp:GridView>`, `runat="server"`) | no .NET Core successor — port to Razor Pages / Blazor |
| inline `<script runat="server">` (runtime compilation) | build-time compilation |
| `System.Data.SqlClient` | `Microsoft.Data.SqlClient` |
| `ConfigurationManager.ConnectionStrings` + `web.config` | `IConfiguration` + `appsettings.json` / env |
| `System.Web` / `HttpContext` page model | ASP.NET Core middleware + DI |
| `Global.asax` `Application_Start` | `Program.cs` / minimal hosting |
| non-SDK `.csproj`, `packages.config`-style refs | SDK-style `<PackageReference>` |
| Windows container | Linux container |

## Package for Transform

```sh
cd environments/sqlmod && rm -rf /tmp/contoso-scoreboard && mkdir /tmp/contoso-scoreboard \
  && cp -R app/. /tmp/contoso-scoreboard/ \
  && (cd /tmp && zip -rq contoso-scoreboard-src.zip contoso-scoreboard -x '*/bin/*' '*/obj/*')
aws s3 cp /tmp/contoso-scoreboard-src.zip \
  s3://fbctf-transform-src-337058058699-use1/contoso-scoreboard-src.zip --profile personal-transform
```

One top-level folder (`contoso-scoreboard/`) inside the zip, as the .NET job expects.
Staged copy also at `~/Downloads/contoso-scoreboard-src.zip`.
