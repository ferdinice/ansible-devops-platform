# ============================================================
# JENKINS MODULE
# ============================================================

# ------------------------------------------------------------
# Get the latest Ubuntu 24.04 LTS AMI
# ------------------------------------------------------------
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

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
# JENKINS SECURITY GROUP
# ============================================================

resource "aws_security_group" "jenkins" {
  name        = "${var.project_name}-jenkins-sg"
  description = "Security group for Jenkins server"
  vpc_id      = var.vpc_id

  # Temporary SSH access from administrator IP.
  # Later we can rely primarily on AWS Systems Manager.
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  # Temporary direct Jenkins access during bootstrap.
  # Later this will be restricted behind the load balancer.
  ingress {
    description     = "Jenkins traffic from ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.jenkins_alb.id]
  }

  # Jenkins requires outbound access for package installation,
  # plugins, GitHub, Maven repositories, etc.
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-jenkins-sg"
    Project = var.project_name
  }
}


# ============================================================
# JENKINS IAM ROLE
# ============================================================

resource "aws_iam_role" "jenkins_ssm_role" {
  name = "${var.project_name}-jenkins-ssm-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "ec2.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name    = "${var.project_name}-jenkins-ssm-role"
    Project = var.project_name
  }
}


# ============================================================
# SSM PERMISSION
# ============================================================

resource "aws_iam_role_policy_attachment" "jenkins_ssm" {
  role       = aws_iam_role.jenkins_ssm_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}


# ============================================================
# JENKINS INSTANCE PROFILE
# ============================================================

resource "aws_iam_instance_profile" "jenkins" {
  name = "${var.project_name}-jenkins-profile"
  role = aws_iam_role.jenkins_ssm_role.name

  tags = {
    Name    = "${var.project_name}-jenkins-profile"
    Project = var.project_name
  }
}


# ============================================================
# JENKINS EC2 SERVER
# ============================================================

resource "aws_instance" "jenkins" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.jenkins.id]

  key_name = var.key_name

  associate_public_ip_address = true

  # Attach Jenkins IAM/SSM permissions to the EC2 instance
  iam_instance_profile = aws_iam_instance_profile.jenkins.name

  # Install and configure Jenkins during EC2 bootstrap
  user_data                   = file("${path.module}/jenkins_userdata.sh")
  user_data_replace_on_change = true

  # Encrypted Jenkins root disk
  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  # Require Instance Metadata Service Version 2
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = {
    Name    = "${var.project_name}-jenkins"
    Project = var.project_name
    Role    = "jenkins"
  }
}

# ============================================================
# ROUTE53 HOSTED ZONE
# ============================================================

data "aws_route53_zone" "main" {
  name         = var.domain_name
  private_zone = false
}


# ============================================================
# ACM CERTIFICATE
# ============================================================

resource "aws_acm_certificate" "jenkins" {
  domain_name       = "${var.jenkins_subdomain}.${var.domain_name}"
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }

  tags = {
    Name    = "${var.project_name}-jenkins-cert"
    Project = var.project_name
  }
}


# ============================================================
# ACM DNS VALIDATION
# ============================================================

resource "aws_route53_record" "jenkins_cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.jenkins.domain_validation_options :
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

resource "aws_acm_certificate_validation" "jenkins" {
  certificate_arn         = aws_acm_certificate.jenkins.arn
  validation_record_fqdns = [for record in aws_route53_record.jenkins_cert_validation : record.fqdn]
}


# ============================================================
# ALB SECURITY GROUP
# ============================================================

resource "aws_security_group" "jenkins_alb" {
  name        = "${var.project_name}-jenkins-alb-sg"
  description = "Allow HTTPS traffic to Jenkins ALB"
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
    Name    = "${var.project_name}-jenkins-alb-sg"
    Project = var.project_name
  }
}


# ============================================================
# APPLICATION LOAD BALANCER
# ============================================================

resource "aws_lb" "jenkins" {
  name               = "jenkins-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.jenkins_alb.id]
  subnets            = var.alb_subnet_ids

  tags = {
    Name    = "${var.project_name}-jenkins-alb"
    Project = var.project_name
  }
}


# ============================================================
# TARGET GROUP
# ============================================================

resource "aws_lb_target_group" "jenkins" {
  name     = "jenkins-target-group"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    path                = "/login"
    protocol            = "HTTP"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    matcher             = "200-399"
  }

  tags = {
    Name    = "${var.project_name}-jenkins-tg"
    Project = var.project_name
  }
}


# ============================================================
# ATTACH JENKINS EC2 TO TARGET GROUP
# ============================================================

resource "aws_lb_target_group_attachment" "jenkins" {
  target_group_arn = aws_lb_target_group.jenkins.arn
  target_id        = aws_instance.jenkins.id
  port             = 8080
}


# ============================================================
# HTTPS LISTENER
# ============================================================

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.jenkins.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.jenkins.certificate_arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.jenkins.arn
  }
}


# ============================================================
# ROUTE53 RECORD
# ============================================================

resource "aws_route53_record" "jenkins" {
  zone_id = data.aws_route53_zone.main.zone_id
  name    = "${var.jenkins_subdomain}.${var.domain_name}"
  type    = "A"

  alias {
    name                   = aws_lb.jenkins.dns_name
    zone_id                = aws_lb.jenkins.zone_id
    evaluate_target_health = true
  }
}