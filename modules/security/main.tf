# Security groups for the fbctf demo — the least-privilege chain from §3.5:
#   internet → alb:80 → web(nginx):80 → [NLB] → app(hhvm):9000 → rds:3306 / memcached:11211
#
# The internal NLB sits between web and app. With client-IP preservation on
# (default for instance targets), app instances see the web instances' source
# IPs, so the web-SG reference works for real traffic — but NLB *health checks*
# come from the NLB nodes' own ENI IPs, so the app SG also allows 9000 from the
# private app subnet CIDRs (where the NLB ENIs live).

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "External ALB: HTTP from the internet"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-alb" }
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from anywhere (443/ACM deferred)"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "alb_all" {
  security_group_id = aws_security_group.alb.id
  description       = "To web tier targets"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_security_group" "web" {
  name        = "${var.name}-web-nginx"
  description = "Web tier (nginx): HTTP from the ALB only"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-web-nginx" }
}

resource "aws_vpc_security_group_ingress_rule" "web_from_alb" {
  security_group_id            = aws_security_group.web.id
  description                  = "HTTP from ALB"
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_vpc_security_group_egress_rule" "web_all" {
  security_group_id = aws_security_group.web.id
  description       = "Boot-time provisioning + FastCGI to app tier via NLB"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_security_group" "app" {
  name        = "${var.name}-app-hhvm"
  description = "App tier (HHVM): FastCGI from web tier and NLB health checks"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-app-hhvm" }
}

resource "aws_vpc_security_group_ingress_rule" "app_from_web" {
  security_group_id            = aws_security_group.app.id
  description                  = "FastCGI from web tier (client IP preserved through NLB)"
  ip_protocol                  = "tcp"
  from_port                    = 9000
  to_port                      = 9000
  referenced_security_group_id = aws_security_group.web.id
}

resource "aws_vpc_security_group_ingress_rule" "app_from_app_subnets" {
  for_each = toset(var.app_subnet_cidrs)

  security_group_id = aws_security_group.app.id
  description       = "FastCGI health checks from NLB nodes"
  ip_protocol       = "tcp"
  from_port         = 9000
  to_port           = 9000
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_egress_rule" "app_all" {
  security_group_id = aws_security_group.app.id
  description       = "Boot-time provisioning + RDS/memcached"
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_security_group" "rds" {
  name        = "${var.name}-rds"
  description = "RDS MySQL: from app tier only"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-rds" }
}

resource "aws_vpc_security_group_ingress_rule" "rds_from_app" {
  security_group_id            = aws_security_group.rds.id
  description                  = "MySQL from app tier"
  ip_protocol                  = "tcp"
  from_port                    = 3306
  to_port                      = 3306
  referenced_security_group_id = aws_security_group.app.id
}

resource "aws_security_group" "memcached" {
  name        = "${var.name}-memcached"
  description = "ElastiCache memcached: from app tier only"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-memcached" }
}

resource "aws_vpc_security_group_ingress_rule" "memcached_from_app" {
  security_group_id            = aws_security_group.memcached.id
  description                  = "Memcached from app tier"
  ip_protocol                  = "tcp"
  from_port                    = 11211
  to_port                      = 11211
  referenced_security_group_id = aws_security_group.app.id
}
