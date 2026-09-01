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

    2. Key the two fbctf app hosts (they are SSM-only; this adds the pubkey,
       fully reversible - remove the line or run `make destroy ENV=discovery-collector`):
       PUB=$(ssh-keygen -y -f ${local_file.discovery_key.filename})
       for i in ${var.discover_fbctf ? "i-01c6e66f6dc9e6da5 i-06ac30d9a470ba4ab" : ""}; do
         aws ssm send-command --instance-ids $i --document-name AWS-RunShellScript \
           --parameters "commands=[\"echo $PUB >> /home/ubuntu/.ssh/authorized_keys\"]"
       done

    3. In the UI: Credentials -> add SSH key /opt/discovery/fbctf-discovery.pem
       for user 'ec2-user', and a second for user 'ubuntu'. Then add a
       "Server import" source with /opt/discovery/import.csv.

    4. Let it run ~1-2 h. Discovered inventory -> Download inventory ->
       discovery_tool_export.zip. Upload that to the migration assessment.

    5. make destroy ENV=discovery-collector
  EOT
}
