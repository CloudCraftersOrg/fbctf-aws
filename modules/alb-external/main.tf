# Internet-facing ALB (§3.2). HTTP-only for now — ACM/443 deferred until a
# hosted zone exists. Health check hits a static asset served by nginx itself,
# NOT /index.php: that would transit nginx→NLB→HHVM→RDS and couple web-tier
# health to a cold app tier (flapping the web ASG during boots).

resource "aws_lb" "this" {
  name               = var.name
  internal           = false
  load_balancer_type = "application"
  subnets            = var.subnet_ids
  security_groups    = [var.security_group_id]
}

resource "aws_lb_target_group" "this" {
  name     = var.name
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  deregistration_delay = 30

  health_check {
    path                = "/static/css/fb-ctf.css"
    matcher             = "200"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }
}
