# ============================================================
# PROMETHEUS MODULE
# ============================================================


# ============================================================
# LATEST UBUNTU 24.04 LTS AMI
# ============================================================

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
# PROMETHEUS SECURITY GROUP
# ============================================================

resource "aws_security_group" "prometheus" {
  name        = "${var.project_name}-prometheus-sg"
  description = "Security group for Prometheus"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Prometheus traffic from shared platform ALB"
    from_port       = 9090
    to_port         = 9090
    protocol        = "tcp"
    security_groups = [var.platform_alb_security_group_id]
  }

  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-prometheus-sg"
    Project = var.project_name
  }
}


# ============================================================
# PROMETHEUS IAM ROLE
# ============================================================

resource "aws_iam_role" "prometheus" {
  name = "${var.project_name}-prometheus-role"

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
    Name    = "${var.project_name}-prometheus-role"
    Project = var.project_name
  }
}


# ============================================================
# SSM PERMISSION
# ============================================================

resource "aws_iam_role_policy_attachment" "prometheus_ssm" {
  role       = aws_iam_role.prometheus.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}


# ============================================================
# PROMETHEUS INSTANCE PROFILE
# ============================================================

resource "aws_iam_instance_profile" "prometheus" {
  name = "${var.project_name}-prometheus-profile"
  role = aws_iam_role.prometheus.name

  tags = {
    Name    = "${var.project_name}-prometheus-profile"
    Project = var.project_name
  }
}


# ============================================================
# PROMETHEUS EC2
# ============================================================

resource "aws_instance" "prometheus" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.prometheus.id]

  associate_public_ip_address = true

  iam_instance_profile = aws_iam_instance_profile.prometheus.name

  user_data                   = file("${path.module}/prometheus_userdata.sh")
  user_data_replace_on_change = true

  root_block_device {
    volume_size = 20
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = {
    Name        = "${var.project_name}-prometheus"
    Project     = var.project_name
    Role        = "prometheus"
    Environment = "management"
  }
}


# ============================================================
# PROMETHEUS TARGET GROUP
# ============================================================

resource "aws_lb_target_group" "prometheus" {
  name     = "prometheus-target-group"
  port     = 9090
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    path                = "/-/healthy"
    protocol            = "HTTP"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = {
    Name    = "${var.project_name}-prometheus-tg"
    Project = var.project_name
  }
}


# ============================================================
# ATTACH PROMETHEUS TO TARGET GROUP
# ============================================================

resource "aws_lb_target_group_attachment" "prometheus" {
  target_group_arn = aws_lb_target_group.prometheus.arn
  target_id        = aws_instance.prometheus.id
  port             = 9090
}