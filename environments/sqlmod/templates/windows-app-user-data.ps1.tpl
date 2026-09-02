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
$sa    = Get-SecretJson '${sa_secret_arn}'
$app   = Get-SecretJson '${app_secret_arn}'
$winrm = Get-SecretJson '${winrm_secret_arn}'
$sqlHost = '${sql_host}'

# A local admin + WinRM HTTPS so the AWS Transform discovery tool can collect
# this Windows / IIS / .NET Framework host.
$wp = ConvertTo-SecureString $winrm.password -AsPlainText -Force
New-LocalUser -Name discovery -Password $wp -PasswordNeverExpires -AccountNeverExpires -ErrorAction SilentlyContinue
Add-LocalGroupMember -Group Administrators -Member discovery -ErrorAction SilentlyContinue
winrm quickconfig -quiet
$cert = New-SelfSignedCertificate -DnsName $env:COMPUTERNAME -CertStoreLocation Cert:\LocalMachine\My
if (-not (Get-ChildItem WSMan:\localhost\Listener | Where-Object { $_.Keys -match 'Transport=HTTPS' })) {
  New-Item -Path WSMan:\localhost\Listener -Transport HTTPS -Address * -Hostname $env:COMPUTERNAME -CertificateThumbPrint $cert.Thumbprint -Force
}
Set-Item WSMan:\localhost\Service\Auth\Basic $true
New-NetFirewallRule -DisplayName "WinRM-HTTP"  -Direction Inbound -LocalPort 5985 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName "WinRM-HTTPS" -Direction Inbound -LocalPort 5986 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue
Restart-Service WinRM

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

# Keep one SQL connection ESTABLISHED + the site warm, so the discovery tool's
# netstat sweep records the .NET-app -> SQL Server dependency edge.
$warm = @'
$cs = "Server=SQLHOST,1433;Database=Scoreboard;User Id=scoreboard_app;Password=APPPW;TrustServerCertificate=True"
while ($true) {
  try {
    $cn = New-Object System.Data.SqlClient.SqlConnection $cs
    $cn.Open()
    while ($cn.State -eq "Open") {
      ($cn.CreateCommand() | % { $_.CommandText="SELECT 1"; $_.ExecuteScalar() }) | Out-Null
      try { Invoke-WebRequest http://localhost/Default.aspx -UseBasicParsing -TimeoutSec 5 | Out-Null } catch {}
      Start-Sleep 15
    }
  } catch { Start-Sleep 10 }
}
'@
$warm = $warm.Replace("SQLHOST", $sqlHost).Replace("APPPW", $app.password)
Set-Content C:\contoso-warm.ps1 $warm
schtasks /create /tn contoso-warm /tr "powershell -NoProfile -WindowStyle Hidden -File C:\contoso-warm.ps1" /sc onstart /ru SYSTEM /f
Start-Process powershell -ArgumentList "-NoProfile -WindowStyle Hidden -File C:\contoso-warm.ps1"

Write-Output "contoso scoreboard ready"
Stop-Transcript
</powershell>
