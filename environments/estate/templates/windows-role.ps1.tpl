<powershell>
# Estate host bootstrap (Windows). Best-effort: brings up the role service
# under the process name the assessment keys on and generates dependency
# edges. Transcript at C:\estate-bootstrap.log; reach the host with SSM.
Start-Transcript -Path C:\estate-bootstrap.log -Append

# Self-terminate: instance_initiated_shutdown_behavior = "terminate".
shutdown.exe /s /t ${max_minutes * 60} /c "estate host max lifetime"

try { Rename-Computer -NewName "${hostname}" -Force -ErrorAction SilentlyContinue } catch {}

%{ for name, ip in hosts_map ~}
Add-Content C:\Windows\System32\drivers\etc\hosts "`r`n${ip} ${name}.corp.local ${name}"
%{ endfor ~}

switch ("${role}") {
  "iis-dotnet" {
    Install-WindowsFeature -Name Web-Server,Web-Asp-Net45,Web-Net-Ext45,Web-Mgmt-Console -IncludeManagementTools
    Import-Module WebAdministration
    New-Item -Path "C:\inetpub\scoreboard" -ItemType Directory -Force | Out-Null
    Set-Content "C:\inetpub\scoreboard\index.aspx" '<%@ Page %><% Response.Write("scoreboard") %>'
    if (-not (Get-Website -Name "scoreboard" -ErrorAction SilentlyContinue)) {
      New-Website -Name "scoreboard" -Port 443 -PhysicalPath "C:\inetpub\scoreboard" -Force
    }
    # Keep an app pool warm so w3wp stays resident.
    $task = 'while ($true) { try { Invoke-WebRequest http://localhost:443/index.aspx -UseBasicParsing } catch {}; Start-Sleep 30 }'
    Set-Content C:\warm.ps1 $task
    schtasks /create /tn estate-warm /tr "powershell -NoProfile -File C:\warm.ps1" /sc onstart /ru SYSTEM /f
    Start-Process powershell -ArgumentList "-NoProfile -File C:\warm.ps1" -WindowStyle Hidden
  }
  "worker" {
    $loop = 'while ($true) { Start-Sleep 30 }'
    Set-Content C:\ScoreWorker.ps1 $loop
    schtasks /create /tn ScoreWorker /tr "powershell -NoProfile -File C:\ScoreWorker.ps1" /sc onstart /ru SYSTEM /f
    Start-Process powershell -ArgumentList "-NoProfile -File C:\ScoreWorker.ps1" -WindowStyle Hidden
  }
  "sqlserver" {
    # SQL Express AMI: service already installed. Ensure it is running and TCP
    # on 1433 is enabled so the dependency edge is real.
    $svc = Get-Service -Name "MSSQL*" | Select-Object -First 1
    if ($svc) {
      try {
        $wmi = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server"
        $inst = (Get-ItemProperty "$wmi\Instance Names\SQL")."SQLEXPRESS"
        $tcp = "$wmi\$inst\MSSQLServer\SuperSocketNetLib\Tcp"
        Set-ItemProperty "$tcp" -Name Enabled -Value 1
        Set-ItemProperty "$tcp\IPAll" -Name TcpPort -Value 1433
      } catch { Write-Output "TCP enable skipped: $_" }
      Restart-Service $svc.Name -Force
    }
  }
}

# Chatter: outbound edges from this host.
$chat = @'
$targets = @(__TARGETS__)
while ($true) {
  foreach ($t in $targets) {
    try { (New-Object Net.Sockets.TcpClient).Connect($t.ip, $t.port) } catch {}
  }
  Start-Sleep 20
}
'@
$chat = $chat.Replace('__TARGETS__', '${chatter_literal}')
Set-Content C:\estate-chatter.ps1 $chat
schtasks /create /tn estate-chatter /tr "powershell -NoProfile -File C:\estate-chatter.ps1" /sc onstart /ru SYSTEM /f
Start-Process powershell -ArgumentList "-NoProfile -File C:\estate-chatter.ps1" -WindowStyle Hidden

%{ if install_agent ~}
try {
  Invoke-WebRequest -Uri "https://s3.${region}.amazonaws.com/aws-discovery-agent.${region}/windows/latest/AWSDiscoveryAgentInstaller.exe" -OutFile C:\ads.exe -UseBasicParsing
  Start-Process C:\ads.exe -ArgumentList "REGION=${region} /quiet" -Wait
} catch { Write-Output "discovery agent install failed: $_" }
%{ endif ~}

Write-Output "estate host ${hostname} (${role}) ready"
Stop-Transcript
</powershell>
