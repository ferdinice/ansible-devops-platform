# ============================================================
# UBUNTU AMI
# ============================================================

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}


# ============================================================
# ROUTE53 ZONE
# ============================================================

data "aws_route53_zone" "main" {
  name         = var.domain_name
  private_zone = false
}


# ============================================================
# NEXUS ALB SECURITY GROUP
# ============================================================

resource "aws_security_group" "nexus_alb" {
  name        = "${var.project_name}-nexus-alb-sg"
  description = "Allow HTTPS access to Nexus ALB"
  vpc_id      = var.vpc_id

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-nexus-alb-sg"
    Project = var.project_name
  }
}


# ============================================================
# NEXUS SERVER SECURITY GROUP
# ============================================================

resource "aws_security_group" "nexus" {
  name        = "${var.project_name}-nexus-sg"
  description = "Allow Nexus traffic only from Nexus ALB"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Nexus UI from ALB"
    from_port       = 8081
    to_port         = 8081
    protocol        = "tcp"
    security_groups = [aws_security_group.nexus_alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-nexus-sg"
    Project = var.project_name
  }
}


# ============================================================
# IAM ROLE FOR SSM
# ============================================================

resource "aws_iam_role" "nexus" {
  name = "${var.project_name}-nexus-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [{
      Effect = "Allow"

      Principal = {
        Service = "ec2.amazonaws.com"
      }

      Action = "sts:AssumeRole"
    }]
  })

  tags = {
    Name    = "${var.project_name}-nexus-role"
    Project = var.project_name
  }
}

resource "aws_iam_role_policy_attachment" "nexus_ssm" {
  role       = aws_iam_role.nexus.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "nexus" {
  name = "${var.project_name}-nexus-profile"
  role = aws_iam_role.nexus.name

  tags = {
    Name    = "${var.project_name}-nexus-profile"
    Project = var.project_name
  }
}


# ============================================================
# NEXUS EC2
# ============================================================

resource "aws_instance" "nexus" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = var.subnet_id
  vpc_security_group_ids      = [aws_security_group.nexus.id]
  key_name                    = var.key_name
  associate_public_ip_address = true
  iam_instance_profile        = aws_iam_instance_profile.nexus.name

  user_data                   = file("${path.module}/nexus_userdata.sh")
  user_data_replace_on_change = true

  root_block_device {
    volume_size = 40
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = {
    Name    = "${var.project_name}-nexus"
    Project = var.project_name
    Role    = "nexus"
  }
}


# ============================================================
# ACM CERTIFICATE
# ============================================================

resource "aws_acm_certificate" "nexus" {
  domain_name       = "${var.nexus_subdomain}.${var.domain_name}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name    = "${var.project_name}-nexus-cert"
    Project = var.project_name
  }
}

resource "aws_route53_record" "nexus_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.nexus.domain_validation_options :
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

resource "aws_acm_certificate_validation" "nexus" {
  certificate_arn         = aws_acm_certificate.nexus.arn
  validation_record_fqdns = [for record in aws_route53_record.nexus_cert_validation : record.fqdn]
}


# ============================================================
# APPLICATION LOAD BALANCER
# ============================================================

resource "aws_lb" "nexus" {
  name               = "nexus-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.nexus_alb.id]
  subnets            = var.alb_subnet_ids

  tags = {
    Name    = "${var.project_name}-nexus-alb"
    Project = var.project_name
  }
}


# ============================================================
# TARGET GROUP
# ============================================================

resource "aws_lb_target_group" "nexus" {
  name     = "nexus-target-group"
  port     = 8081
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    path                = "/"
    protocol            = "HTTP"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    matcher             = "200-399"
  }

  tags = {
    Name    = "${var.project_name}-nexus-tg"
    Project = var.project_name
  }
}

resource "aws_lb_target_group_attachment" "nexus" {
  target_group_arn = aws_lb_target_group.nexus.arn
  target_id        = aws_instance.nexus.id
  port             = 8081
}


# ============================================================
# HTTPS LISTENER
# ============================================================

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.nexus.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.nexus.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.nexus.arn
  }
}


# ============================================================
# ROUTE53
# ============================================================

resource "aws_route53_record" "nexus" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "${var.nexus_subdomain}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.nexus.dns_name
    zone_id                = aws_lb.nexus.zone_id
    evaluate_target_health = true
  }
}