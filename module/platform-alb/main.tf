# ============================================================
# ROUTE53 HOSTED ZONE
# ============================================================

data "aws_route53_zone" "main" {
  name         = var.domain_name
  private_zone = false
}


# ============================================================
# SHARED PLATFORM ALB SECURITY GROUP
# ============================================================

resource "aws_security_group" "platform_alb" {
  name        = "${var.project_name}-platform-alb-sg"
  description = "Shared ALB security group for platform services"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-platform-alb-sg"
    Project = var.project_name
  }
}


# ============================================================
# SHARED APPLICATION LOAD BALANCER
# ============================================================

resource "aws_lb" "platform" {
  name               = "platform-alb"
  internal           = false
  load_balancer_type = "application"

  security_groups = [
    aws_security_group.platform_alb.id
  ]

  subnets = var.public_subnet_ids

  tags = {
    Name    = "${var.project_name}-platform-alb"
    Project = var.project_name
  }
}


# ============================================================
# SHARED WILDCARD ACM CERTIFICATE
# ============================================================

resource "aws_acm_certificate" "platform" {
  domain_name       = "*.${var.domain_name}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name    = "${var.project_name}-platform-cert"
    Project = var.project_name
  }
}


# ============================================================
# ACM DNS VALIDATION
# ============================================================

resource "aws_route53_record" "certificate_validation" {
  for_each = {
    for dvo in aws_acm_certificate.platform.domain_validation_options :
    dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = data.aws_route53_zone.main.zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]
}


resource "aws_acm_certificate_validation" "platform" {
  certificate_arn = aws_acm_certificate.platform.arn

  validation_record_fqdns = [
    for record in aws_route53_record.certificate_validation :
    record.fqdn
  ]
}


# ============================================================
# SHARED HTTPS LISTENER
# ============================================================

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.platform.arn
  port              = 443
  protocol          = "HTTPS"

  ssl_policy      = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn = aws_acm_certificate_validation.platform.certificate_arn

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "text/plain"
      message_body = "Platform service not found"
      status_code  = "404"
    }
  }
}