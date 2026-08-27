# AI-agent brief: AWS architecture diagram for the fbctf demo deployment

You are producing a **single architecture diagram** of a deployed AWS
environment. Everything you need is in this brief — do not invent components,
and do not omit any listed here. The system is a deliberately legacy 2018 PHP
(HHVM) application deployed as the "before" state for an AWS Transform
modernization demo.

## Output

- Preferred: a **diagrams.net (draw.io) XML file** using the official AWS 2024+
  icon/shape library. Acceptable alternatives (in order): Python `diagrams`
  (mingrammer) script rendering to PNG/SVG, or high-quality Mermaid
  `architecture-beta`/flowchart if the tooling supports AWS icons.
- Landscape orientation, legible at one glance on a slide (16:9). Official AWS
  service icons only; consistent icon size.
- Title block: **"fbctf on AWS — AWS Transform demo ('before' state)"**,
  subtitle "Account 337058058699 (Sandbox) · us-east-1 · Terraform".

## Containment hierarchy (draw as nested groups)

```
AWS Cloud (account 337058058699, us-east-1)
└── VPC "fbctf-demo" — 10.20.0.0/16
    ├── AZ us-east-1a (left column)      ├── AZ us-east-1b (right column)
    │   ├── Public subnet 10.20.0.0/24   │   ├── Public subnet 10.20.1.0/24
    │   ├── App subnet   10.20.10.0/24   │   ├── App subnet   10.20.11.0/24
    │   └── Data subnet  10.20.20.0/24   │   └── Data subnet  10.20.21.0/24
```

Draw the three subnet tiers as horizontal bands (public on top, private-app
middle, private-data bottom), each band spanning both AZ columns. Use AWS
standard colors: green public subnets, blue private subnets.

## Components

**Outside the VPC (left/top edge):**
| # | Component | Icon | Label |
|---|---|---|---|
| 1 | Users / Internet | Users icon | "Players + admin (HTTP only)" |
| 2 | Internet Gateway | IGW | attached to VPC edge |

**Public subnet band:**
| 3 | Application Load Balancer | ALB icon (spans both public subnets) | "fbctf-demo-web · HTTP :80 (ACM/443 deferred)" |
| 4 | NAT Gateway | NAT icon, in 10.20.0.0/24 ONLY (single NAT — cost tradeoff) | "single NAT" |

**Private app subnet band:**
| 5 | Auto Scaling group "web" | ASG group containing an EC2 icon | "nginx · Ubuntu 16.04 (EOL) · t3.small · min1/max2" |
| 6 | Network Load Balancer (internal) | NLB icon (spans both app subnets) | "fbctf-demo-app · TCP :9000 · FastCGI · client-IP preservation OFF" |
| 7 | Auto Scaling group "app" | ASG group containing an EC2 icon | "HHVM 3.21 · Ubuntu 16.04 (EOL) · t3.medium · min1/max2" |

**Private data subnet band:**
| 8 | RDS MySQL | RDS icon | "MySQL 8.0 · db.t3.small · single-AZ · mysql_native_password" |
| 9 | ElastiCache | ElastiCache icon | "memcached · cache.t3.micro · 1 node" |

**Regional services (right side, outside the VPC, inside AWS Cloud):**
| 10 | S3 | bucket icon | "artifacts: prebuilt app tarball, vendored HHVM .debs, Node 6, SQL" |
| 11 | S3 | second bucket icon | "Terraform state" |
| 12 | Secrets Manager | icon | "RDS master (rds!…) · app DB user · scoreboard admin password" |
| 13 | Systems Manager | icon | "Parameter Store /fbctf/* · Session Manager (no SSH, no bastion)" |
| 14 | CloudWatch | icon | "Logs: /fbctf/{hhvm,nginx,user-data} · 5 alarms (ALB 5xx, 2× unhealthy hosts, RDS CPU/storage)" |
| 15 | IAM | icon | "instance roles fbctf-demo-{web,app} — S3 read, /fbctf/* params; app also reads DB secrets" |

**Optional annotation (dotted box, clearly marked "future"):** AWS Transform
workspace, us-east-1 — the demo's modernization tool, same account/region.

## Connections (every arrow, with label; direction = initiator → target)

**Runtime request path (bold/solid arrows, number them 1–5):**
1. Users → ALB — "HTTP :80"
2. ALB → web ASG — "HTTP :80 · health: GET /static/css/fb-ctf.css"
3. web (nginx) → NLB — "FastCGI TCP :9000"
4. NLB → app ASG — "TCP :9000 · TCP health checks from NLB ENIs"
5a. app (HHVM) → RDS — "MySQL :3306"
5b. app (HHVM) → ElastiCache — "memcached :11211"

**Boot-time provisioning (dashed arrows, distinct color):**
- web ASG and app ASG → S3 artifacts — "boot: fetch prebuilt app tarball"
- app ASG → Secrets Manager — "boot: DB credentials + admin password"
- web/app ASG → SSM Parameter Store — "boot: /fbctf/* endpoints"
- web/app ASG → NAT → IGW → Internet — "boot: dl.hhvm.com, archive.ubuntu.com (Xenial), deb.nodesource.com, npm" (one dashed arrow via the NAT is enough; label it)

**Operations (dotted, thin):**
- web/app ASG → CloudWatch — "CW agent: logs"
- Operator (small person icon near title) → SSM Session Manager → EC2 — "shell access (no SSH)"

**Security-group chain**: render as a small callout table or edge annotations —
`ALB←0.0.0.0/0:80 · web←ALB:80 · app←web+app-subnet CIDRs:9000 · RDS←app:3306 · MC←app:11211`.

## Styling rules

- Runtime path numbered and visually dominant; boot-time dashed; ops dotted.
- Tag the two EC2 tiers with a small ⚠ "EOL OS — destroy after each demo".
- Do not draw route tables or individual ENIs. Do not draw a VPN/DirectConnect
  (none exists). No VPC endpoints exist — S3/SSM traffic flows via the NAT.
- Legend box: solid=runtime, dashed=boot-time provisioning, dotted=operations.

## Validation checklist (self-check before you finish)

- [ ] 15 numbered components all present; nothing extra invented
- [ ] ALB is internet-facing in PUBLIC subnets; NLB is INTERNAL in APP subnets
- [ ] Arrow 3 goes nginx→NLB (never nginx→HHVM directly, never ALB→NLB)
- [ ] RDS and ElastiCache only receive from the app tier
- [ ] Exactly ONE NAT gateway, in one AZ only
- [ ] HTTP only at the edge — no ACM/443/Route53 anywhere
- [ ] EOL warnings on both EC2 tiers; legend present; title block present
