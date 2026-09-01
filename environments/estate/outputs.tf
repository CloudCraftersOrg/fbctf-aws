output "linux_hosts" {
  description = "name => { id, private_ip }"
  value       = { for k, m in module.linux_host : k => { id = m.id, ip = m.private_ip } }
}

output "windows_hosts" {
  value = { for k, m in module.windows_host : k => { id = m.id, ip = m.private_ip } }
}

output "private_zone" {
  value = aws_route53_zone.corp.name
}

output "self_terminates_after_minutes" {
  value = var.max_lifetime_minutes
}

output "next_steps" {
  value = <<-EOT
    Hosts are SSM targets: aws ssm start-session --target <id>

    - Confirm role processes:  ps -ef | grep -E 'redis-server|beam.smp|java|cobcrun'
      (Windows: Get-Process w3wp,sqlservr,powershell)
    - Confirm edges:           ss -tnp | grep ESTAB     (netstat on Windows)
    - Point a Transform assessment at this account, or import ../../inventory/out/*.csv
    - terraform destroy  (or wait ${var.max_lifetime_minutes}m for self-termination)
  EOT
}
