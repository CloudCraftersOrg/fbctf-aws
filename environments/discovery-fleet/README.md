# discovery-fleet — prove the live agent path

`inventory/` covers discovery by **MPA import**. This env covers discovery by
**live agent** — the other supported Transform input — with a throwaway fleet
that costs about **$0.10 per run** and deletes itself.

## What it creates

| Resource | Detail |
|---|---|
| VPC + 1 public subnet + IGW | `10.60.0.0/16`, **no NAT gateway** |
| `node_count` × EC2 (default 4) | `t4g.nano` **spot**, Amazon Linux 2023 arm64 |
| Instance profile `fbctf-discovery-agent` | `AmazonSSMManagedInstanceCore` + `AWSApplicationDiscoveryAgentAccess` |
| user-data | installs the AWS Application Discovery Agent; runs a 15s inter-node chatter loop so netstat dependency capture has edges |

Every node runs `shutdown -h +180` at boot and the launch template terminates
on shutdown, so the fleet is gone within `max_lifetime_minutes` **whether or not
you remember `terraform destroy`**.

## Run

```sh
cp environments/discovery-fleet/terraform.tfvars.example environments/discovery-fleet/terraform.tfvars
make init  ENV=discovery-fleet
make apply ENV=discovery-fleet
# ... ~30-60 min of collection ...
make destroy ENV=discovery-fleet          # optional — it self-terminates anyway
```

## Verify

1. **Migration Hub** (us-east-1) → **Discover → Data collectors** — the agents
   should show *Collecting*.
2. **Discover → Servers** — the nodes appear with CPU/RAM/disk and, after a
   while, network connections between them.
3. Import that discovery data into a Transform assessment, or run it alongside
   the `inventory/` CSV import to show both paths.

## Caveats

- If the agent does not register from the instance role, finish **Migration Hub
  → Settings → Data collectors** setup and re-check; the agent install is
  best-effort and logged to `/var/log/user-data.log` on each node
  (`aws ssm start-session --target <id>`).
- Application Discovery Service is us-east-1 for this account — the `region`
  variable is pinned there.
- This fleet is **not** the 14-server estate. It is 4 near-identical nodes whose
  only job is to prove agent discovery + dependency capture work. Wave planning,
  right-sizing variety and TCO come from `inventory/`.
