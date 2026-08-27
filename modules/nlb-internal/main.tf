# Internal NLB between nginx and HHVM (ADR 002): FastCGI is not HTTP, so the
# balancer must be L4. Client IP preservation is OFF so the source seen by app
# instances is always the NLB nodes' ENI IPs (covered by the app SG's
# subnet-CIDR rules) — this also avoids the classic single-instance hairpin
# failure when a target connects to itself through the NLB.

resource "aws_lb" "this" {
  name               = var.name
  internal           = true
  load_balancer_type = "network"
  subnets            = var.subnet_ids

  enable_cross_zone_load_balancing = true
}

resource "aws_lb_target_group" "this" {
  name     = var.name
  port     = 9000
  protocol = "TCP"
  vpc_id   = var.vpc_id

  preserve_client_ip = false

  deregistration_delay = 30

  health_check {
    protocol            = "TCP"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    interval            = 10
  }
}

resource "aws_lb_listener" "this" {
  load_balancer_arn = aws_lb.this.arn
  port              = 9000
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}
