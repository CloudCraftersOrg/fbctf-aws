<powershell>
Start-Transcript -Path C:\discovery-setup.log -Append

# self-terminate (instance_initiated_shutdown_behavior = terminate)
shutdown.exe /s /t ${max_minutes * 60} /c "discovery windows max lifetime"

$pw = ConvertTo-SecureString '${admin_password}' -AsPlainText -Force

# discovery credential: a local admin the AWS Transform discovery tool uses over WinRM
New-LocalUser -Name discovery -Password $pw -PasswordNeverExpires -AccountNeverExpires -ErrorAction SilentlyContinue
Add-LocalGroupMember -Group Administrators -Member discovery -ErrorAction SilentlyContinue
try { Set-LocalUser -Name Administrator -Password $pw } catch {}

# WinRM: HTTP (5985) + HTTPS (5986, self-signed) so NTLM works
winrm quickconfig -quiet
$cert = New-SelfSignedCertificate -DnsName $env:COMPUTERNAME -CertStoreLocation Cert:\LocalMachine\My
$existing = Get-ChildItem WSMan:\localhost\Listener | Where-Object { $_.Keys -match 'Transport=HTTPS' }
if (-not $existing) {
  New-Item -Path WSMan:\localhost\Listener -Transport HTTPS -Address * -Hostname $env:COMPUTERNAME -CertificateThumbPrint $cert.Thumbprint -Force
}
Set-Item WSMan:\localhost\Service\Auth\Basic $true
Set-Item WSMan:\localhost\Service\AllowUnencrypted $true
New-NetFirewallRule -DisplayName "WinRM-HTTP"  -Direction Inbound -LocalPort 5985 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue
New-NetFirewallRule -DisplayName "WinRM-HTTPS" -Direction Inbound -LocalPort 5986 -Protocol TCP -Action Allow -ErrorAction SilentlyContinue
Restart-Service WinRM

# IIS so the discovery tool sees w3wp + an HTTP tier
Install-WindowsFeature -Name Web-Server,Web-Asp-Net45 -IncludeManagementTools
Set-Content C:\inetpub\wwwroot\index.aspx '<%@ Page %><% Response.Write("contoso") %>'

# SQL Server 2022 Express ships in the AMI - make sure it is up and on TCP 1433
$svc = Get-Service 'MSSQL*' | Select-Object -First 1
if ($svc) {
  try {
    $inst = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\Instance Names\SQL')."SQLEXPRESS"
    $tcp  = "HKLM:\SOFTWARE\Microsoft\Microsoft SQL Server\$inst\MSSQLServer\SuperSocketNetLib\Tcp"
    Set-ItemProperty $tcp -Name Enabled -Value 1
    Set-ItemProperty "$tcp\IPAll" -Name TcpPort -Value 1433
  } catch {}
  Set-Service $svc.Name -StartupType Automatic
  Restart-Service $svc.Name -Force
}

# keep w3wp warm and hold connections to peers so netstat records the edges
$warm = 'while ($true) { try { Invoke-WebRequest http://localhost/index.aspx -UseBasicParsing | Out-Null } catch {}; Start-Sleep 20 }'
Set-Content C:\warm.ps1 $warm
schtasks /create /tn contoso-warm /tr "powershell -NoProfile -File C:\warm.ps1" /sc onstart /ru SYSTEM /f
Start-Process powershell -ArgumentList '-NoProfile -File C:\warm.ps1' -WindowStyle Hidden

$peers = '${peer_ips}'.Split(',') | Where-Object { $_ }
$chat = @"
`$peers = @('$($peers -join "','")')
while (`$true) {
  foreach (`$p in `$peers) {
    try { `$c = New-Object Net.Sockets.TcpClient; `$c.Connect(`$p, 1433); Start-Sleep 300; `$c.Close() } catch {}
  }
}
"@
Set-Content C:\chat.ps1 $chat
schtasks /create /tn contoso-chat /tr "powershell -NoProfile -File C:\chat.ps1" /sc onstart /ru SYSTEM /f
Start-Process powershell -ArgumentList '-NoProfile -File C:\chat.ps1' -WindowStyle Hidden

Write-Output "discovery windows ready"
Stop-Transcript
</powershell>
