# --- Security group (public) ---
resource "aws_security_group" "this" {
  name_prefix = "${var.name}-alb-"
  description = "Public ALB"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-alb" }

  lifecycle {
    create_before_destroy = true
    
  }
}


resource "aws_vpc_security_group_ingress_rule" "http" {
  security_group_id = aws_security_group.this.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "to_vpc" {
  security_group_id = aws_security_group.this.id
  cidr_ipv4         = var.vpc_cidr
  ip_protocol       = "-1"
}

# --- Load balancer ---
resource "aws_lb" "this" {
  name                       = "${var.name}-alb"
  load_balancer_type         = "application"
  internal                   = false
  security_groups            = [aws_security_group.this.id]
  subnets                    = var.public_subnet_ids
  drop_invalid_header_fields = true
  enable_deletion_protection = var.deletion_protection
}

# --- Target groups (har service ka ek) ---
resource "aws_lb_target_group" "this" {
  for_each = var.services

  name                 = "${var.name}-${each.key}"
  port                 = each.value.port
  protocol             = "HTTP"
  target_type          = "ip" # Fargate (awsvpc) ke liye "ip" hi hota hai
  vpc_id               = var.vpc_id
  deregistration_delay = 30

  health_check {
    path                = each.value.health_check_path
    matcher             = "200-399"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  # dynamic block: stickiness sirf jahan true ho
  dynamic "stickiness" {
    for_each = each.value.stickiness ? [1] : []
    content {
      type            = "lb_cookie"
      enabled         = true
      cookie_duration = 86400
    }
  }
}

# --- Listener + path rules ---
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[var.default_service].arn
  }
}

resource "aws_lb_listener_rule" "this" {
  for_each = { for k, v in var.services : k => v if length(v.path_patterns) > 0 }

  listener_arn = aws_lb_listener.http.arn
  priority     = each.value.priority

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[each.key].arn
  }

  condition {
    path_pattern {
      values = each.value.path_patterns
    }
  }
}