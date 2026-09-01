output "node_instance_ids" {
  description = "SSM targets for the collector nodes"
  value       = aws_instance.node[*].id
}

output "node_private_ips" {
  value = aws_instance.node[*].private_ip
}

output "self_terminates_after_minutes" {
  description = "Each node runs `shutdown -h +N` at boot; the launch template terminates on shutdown"
  value       = var.max_lifetime_minutes
}

output "next_steps" {
  value = <<-EOT
    1. Migration Hub (us-east-1) -> Discover -> Data collectors: confirm the
       ${var.node_count} agents report "Collecting".
    2. Give it ~30-60 min, then check Discover -> Servers for the nodes and
       their network connections.
    3. `make destroy ENV=discovery-fleet` — or leave it; it self-terminates at
       the time above.
  EOT
}
