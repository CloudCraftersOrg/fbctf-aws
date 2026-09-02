output "collector_instance_id" {
  value = aws_instance.collector.id
}

output "ui_url" {
  description = "Reach it with an SSM port-forward (see next_steps) unless ui_allow_cidr was set"
  value       = "https://${aws_instance.collector.private_ip}:5000"
}

output "ssh_key_file" {
  description = "Private key for the OS credential in the discovery tool UI"
  value       = local_file.discovery_key.filename
}

output "import_csv" {
  value = join("\n", concat(
    ["hostname_or_ip,os_credential_name,oracle_credential_name"],
    [for t in local.all_targets : "${t.ip},,"]
  ))
}

output "targets" {
  value = { for t in local.all_targets : t.name => t.ip }
}

output "windows_target" {
  description = "WinRM credential for the discovery tool: username 'discovery', NTLM over HTTPS (5986)"
  value = var.enable_windows ? {
    ip       = local.windows_ip
    username = "discovery"
    password = random_password.windows[0].result
  } : null
  sensitive = true
}

output "next_steps" {
  value = <<-EOT
    1. Port-forward the UI:
       aws ssm start-session --target ${aws_instance.collector.id} \
         --document-name AWS-StartPortForwardingSession \
         --parameters '{"portNumber":["5000"],"localPortNumber":["5000"]}'
       then open https://localhost:5000 (self-signed cert), set a password.

    2. Key the Linux hosts in the peered stacks (they are SSM-only; this adds the
       pubkey, fully reversible - remove the line or `make destroy ENV=<stack>`):
       PUB=$(ssh-keygen -y -f ${local_file.discovery_key.filename})
       for i in ${join(" ", concat(
  var.discover_sqlmod ? [data.aws_instance.sqlmod_sqlserver[0].id] : [],
  var.discover_oramod ? [data.aws_instance.oramod_oracle[0].id, data.aws_instance.oramod_app[0].id] : [],
))}; do   # Amazon Linux -> ec2-user
         aws ssm send-command --instance-ids $i --document-name AWS-RunShellScript \
           --parameters "commands=[\"echo $PUB >> /home/ec2-user/.ssh/authorized_keys\"]"
       done
       %{if var.discover_sqlmod~}
       aws ssm send-command --instance-ids ${data.aws_instance.sqlmod_wordpress[0].id} --document-name AWS-RunShellScript \
         --parameters "commands=[\"echo $PUB >> /home/ubuntu/.ssh/authorized_keys\"]"   # Ubuntu -> ubuntu
       The Contoso app host (Windows) is collected over WinRM: add a WinRM credential,
       user 'discovery', password from Secrets Manager fbctf-sqlmod/app-winrm.
       %{endif~}

    3. In the UI: Credentials -> add SSH key /opt/discovery/fbctf-discovery.pem
       for user 'ec2-user', and a second for user 'ubuntu'. Then add a
       "Server import" source with /opt/discovery/import.csv.

    4. Let it run ~1-2 h. Discovered inventory -> Download inventory ->
       discovery_tool_export.zip. Upload that to the migration assessment.

    5. make destroy ENV=discovery-collector
  EOT
}
