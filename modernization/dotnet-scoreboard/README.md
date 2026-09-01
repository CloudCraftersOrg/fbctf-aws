# dotnet-scoreboard — .NET Framework → .NET modernization fixture

A CTF scoreboard as a classic on-premises .NET Framework app: an ASP.NET MVC 5
web project and a WCF service, in one solution, targeting `net48`.

```
ContosoScoreboard.sln
src/
  ContosoScoreboard.Web/            ASP.NET MVC 5 front-end
    Controllers/ScoreboardController.cs
    Models/{Team,ScoreboardContext}.cs   Entity Framework 6, code-first
    Services/BadgeRenderer.cs        System.Drawing — Windows-only
    App_Start/RouteConfig.cs
    Global.asax.cs
    Web.config  +  Web.Release.config  (config transforms)
    packages.config
  ContosoScoreboard.ScoringService/  WCF service (.svc)
    IScoringService.cs
    ScoringService.svc.cs
```

## Why this forces a real transformation

| Construct | Where | What the agent must do |
|---|---|---|
| `packages.config` + non-SDK `.csproj` | both projects | convert to SDK-style `<PackageReference>` |
| `System.Web` / `HttpContext.Current` | `ScoreboardController`, `Global.asax` | move to ASP.NET Core `HttpContext` injection |
| `System.Drawing.Graphics` | `BadgeRenderer` | swap for a cross-platform imaging library (Windows-only API) |
| Entity Framework 6, `DbContext` in a static field | `ScoreboardContext` | EF Core + DI-scoped context |
| `Web.config` connection strings + `<system.web>` | `Web.config` | `appsettings.json` + options pattern |
| `Web.Release.config` XDT transform | | environment config, not build-time XML rewriting |
| WCF `[ServiceContract]` / `.svc` | `ScoringService` | CoreWCF, or a minimal API / gRPC port |
| `Global.asax` `Application_Start` | | `Program.cs` startup |

## Target

`.NET 8`, Linux container, for the `contoso-web-01` + `contoso-app-01/02` move
group in the assessment. The worker on `contoso-worker-01` (.NET 4.5) shares the
same transformation path and is out of scope for this fixture only to keep it
small.
