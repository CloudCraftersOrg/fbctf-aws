<powershell>
Start-Transcript -Path C:\app-setup.log -Append
$ErrorActionPreference = 'Stop'
Import-Module AWSPowerShell

%{ if max_minutes > 0 ~}
shutdown.exe /s /t ${max_minutes * 60} /c "contoso app max lifetime"
%{ endif ~}

Install-WindowsFeature -Name Web-Server,Web-Asp-Net45,Web-Mgmt-Console -IncludeManagementTools

function Get-SecretJson($id) {
  (Get-SECSecretValue -SecretId $id -Region ${region}).SecretString | ConvertFrom-Json
}
$sa  = Get-SecretJson '${sa_secret_arn}'
$app = Get-SecretJson '${app_secret_arn}'
$sqlHost = '${sql_host}'

# App-scoped SQL login (the app never connects as sa). Done here because the SQL
# Server host's user-data is not re-run on template edits.
function Invoke-Sql($db, $sql) {
  $cs = "Server=$sqlHost,1433;Database=$db;User Id=sa;Password=$($sa.password);TrustServerCertificate=True;Connection Timeout=10"
  for ($i = 0; $i -lt 30; $i++) {
    try {
      $cn = New-Object System.Data.SqlClient.SqlConnection $cs
      $cn.Open()
      $cmd = $cn.CreateCommand(); $cmd.CommandText = $sql; $cmd.ExecuteNonQuery() | Out-Null
      $cn.Close(); return
    } catch { Start-Sleep 10 }
  }
  throw "SQL not reachable at $sqlHost"
}
Invoke-Sql 'master' @"
IF NOT EXISTS (SELECT 1 FROM sys.server_principals WHERE name = 'scoreboard_app')
    CREATE LOGIN scoreboard_app WITH PASSWORD = '$($app.password)', CHECK_POLICY = OFF;
"@
Invoke-Sql 'Scoreboard' @"
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = 'scoreboard_app')
    CREATE USER scoreboard_app FOR LOGIN scoreboard_app;
GRANT SELECT, EXECUTE TO scoreboard_app;
"@

Remove-Item C:\inetpub\wwwroot\* -Recurse -Force -ErrorAction SilentlyContinue
Read-S3Object -BucketName '${schema_bucket}' -Key 'app/Default.aspx' -File 'C:\inetpub\wwwroot\Default.aspx' -Region ${region}
Read-S3Object -BucketName '${schema_bucket}' -Key 'app/web.config'   -File 'C:\inetpub\wwwroot\web.config'   -Region ${region}

$conn = "Server=$sqlHost,1433;Database=Scoreboard;User Id=scoreboard_app;Password=$($app.password);TrustServerCertificate=True"
(Get-Content C:\inetpub\wwwroot\web.config) -replace '__CONNSTRING__', $conn | Set-Content C:\inetpub\wwwroot\web.config

iisreset
Write-Output "contoso scoreboard ready"
Stop-Transcript
</powershell>
