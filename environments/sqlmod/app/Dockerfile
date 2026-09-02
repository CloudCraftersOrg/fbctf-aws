# Current state - ASP.NET Web Forms on .NET Framework 4.8, a Windows container.
# AWS Transform's modernization target is a Linux .NET 8 container.
FROM mcr.microsoft.com/dotnet/framework/aspnet:4.8-windowsservercore-ltsc2022
WORKDIR C:\\inetpub\\wwwroot
COPY Default.aspx web.config ./
# Connection string is injected at runtime (the running host substitutes
# __CONNSTRING__ in web.config; a container would use an env var + config).
