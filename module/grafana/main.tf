# ============================================================
# GRAFANA MODULE
# ============================================================


# ============================================================
# UBUNTU 24.04 LTS AMI
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
# GRAFANA SECURITY GROUP
# ============================================================

resource "aws_security_group" "grafana" {
  name        = "${var.project_name}-grafana-sg"
  description = "Security group for Grafana"
  vpc_id      = var.vpc_id

  ingress {
    description     = "Grafana traffic from shared platform ALB"
    from_port       = 3000
    to_port         = 3000
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
    Name    = "${var.project_name}-grafana-sg"
    Project = var.project_name
  }
}


# ============================================================
# GRAFANA IAM ROLE / SSM
# ============================================================

resource "aws_iam_role" "grafana" {
  name = "${var.project_name}-grafana-role"

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
    Name    = "${var.project_name}-grafana-role"
    Project = var.project_name
  }
}

resource "aws_iam_role_policy_attachment" "grafana_ssm" {
  role       = aws_iam_role.grafana.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "grafana" {
  name = "${var.project_name}-grafana-profile"
  role = aws_iam_role.grafana.name

  tags = {
    Name    = "${var.project_name}-grafana-profile"
    Project = var.project_name
  }
}


# ============================================================
# GRAFANA EC2
# ============================================================

resource "aws_instance" "grafana" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.grafana.id]

  associate_public_ip_address = true

  iam_instance_profile = aws_iam_instance_profile.grafana.name

  user_data = templatefile(
    "${path.module}/grafana_userdata.sh",
    {
      prometheus_ip  = var.prometheus_private_ip
      dashboard_json = file("${path.module}/dashboards/platform-overview.json")
    }
  )

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
    Name        = "${var.project_name}-grafana"
    Project     = var.project_name
    Role        = "grafana"
    Environment = "management"
  }
}


# ============================================================
# GRAFANA TARGET GROUP
# ============================================================

resource "aws_lb_target_group" "grafana" {
  name     = "grafana-target-group"
  port     = 3000
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    path                = "/api/health"
    protocol            = "HTTP"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200"
  }

  tags = {
    Name    = "${var.project_name}-grafana-tg"
    Project = var.project_name
  }
}


# ============================================================
# ATTACH GRAFANA TO TARGET GROUP
# ============================================================

resource "aws_lb_target_group_attachment" "grafana" {
  target_group_arn = aws_lb_target_group.grafana.arn
  target_id        = aws_instance.grafana.id
  port             = 3000
}
