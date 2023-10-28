resource "aws_lb" "nagaza-prod" {
  name               = "nagaza-prod-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.nagaza-prod-alb-sg.id]
  subnets            = [for subnet in aws_subnet.public : subnet.id]

  enable_deletion_protection = false

  tags = {
    Environment = "production"
  }
}

resource "aws_security_group" "nagaza-prod-alb-sg" {
  name        = "nagaza-prod-alb-sg"
  description = "Prod ALB Security Group"
  vpc_id      = aws_vpc.nagaza-vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "nagaza-prod-alb-sg"
  }
}

resource "aws_lb_target_group" "nagaza-prod" {
  name     = "nagaza-prod-alb-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.nagaza-vpc.id
  target_type = "ip"

  health_check {
    enabled             = true
    interval            = 30
    path                = "/"
    timeout             = 10
    matcher             = "200"
    healthy_threshold   = 5
    unhealthy_threshold = 5
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_listener" "https_forward" {
  load_balancer_arn = aws_lb.nagaza-prod.arn
  ssl_policy        = "ELBSecurityPolicy-2015-05"
  certificate_arn = local.alb_certificate_arn
  port              = 443
  protocol          = "HTTPS"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nagaza-prod.arn
  }
}

resource "aws_lb_listener" "http_to_https" {
  load_balancer_arn = aws_lb.nagaza-prod.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}
