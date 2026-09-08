# ============================================================
# SONARQUBE MODULE
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
# SONARQUBE SECURITY GROUP
# ============================================================

resource "aws_security_group" "sonarqube" {
  name        = "${var.project_name}-sonarqube-sg"
  description = "Security group for SonarQube"
  vpc_id      = var.vpc_id

  ingress {
    description     = "SonarQube traffic from shared platform ALB"
    from_port       = 9000
    to_port         = 9000
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
    Name    = "${var.project_name}-sonarqube-sg"
    Project = var.project_name
  }
}


# ============================================================
# SONARQUBE IAM ROLE
# ============================================================

resource "aws_iam_role" "sonarqube" {
  name = "${var.project_name}-sonarqube-role"

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
    Name    = "${var.project_name}-sonarqube-role"
    Project = var.project_name
  }
}


# ============================================================
# SSM PERMISSION
# ============================================================

resource "aws_iam_role_policy_attachment" "sonarqube_ssm" {
  role       = aws_iam_role.sonarqube.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}


# ============================================================
# SONARQUBE INSTANCE PROFILE
# ============================================================

resource "aws_iam_instance_profile" "sonarqube" {
  name = "${var.project_name}-sonarqube-profile"
  role = aws_iam_role.sonarqube.name

  tags = {
    Name    = "${var.project_name}-sonarqube-profile"
    Project = var.project_name
  }
}


# ============================================================
# SONARQUBE EC2
# ============================================================

resource "aws_instance" "sonarqube" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.sonarqube.id]

  associate_public_ip_address = true

  iam_instance_profile = aws_iam_instance_profile.sonarqube.name

  user_data                   = file("${path.module}/sonarqube_userdata.sh")
  user_data_replace_on_change = true

  root_block_device {
    volume_size = 30
    volume_type = "gp3"
    encrypted   = true
  }

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = {
    Name    = "${var.project_name}-sonarqube"
    Project = var.project_name
    Role    = "sonarqube"
  }
}


# ============================================================
# SONARQUBE TARGET GROUP
# ============================================================

resource "aws_lb_target_group" "sonarqube" {
  name     = "sonarqube-target-group"
  port     = 9000
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    path                = "/"
    protocol            = "HTTP"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
    matcher             = "200-399"
  }

  tags = {
    Name    = "${var.project_name}-sonarqube-tg"
    Project = var.project_name
  }
}


# ============================================================
# ATTACH SONARQUBE TO TARGET GROUP
# ============================================================

resource "aws_lb_target_group_attachment" "sonarqube" {
  target_group_arn = aws_lb_target_group.sonarqube.arn
  target_id        = aws_instance.sonarqube.id
  port             = 9000
}