# ============================================================
# JENKINS MODULE
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
# JENKINS SECURITY GROUP
# ============================================================

resource "aws_security_group" "jenkins" {
  name        = "${var.project_name}-jenkins-sg"
  description = "Security group for Jenkins server"
  vpc_id      = var.vpc_id

  # Temporary SSH access.
  # We can remove this later because SSM is already available.
  ingress {
    description = "SSH access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_cidr]
  }

  # Jenkins UI/API may only be reached through the shared ALB.
  ingress {
    description     = "Jenkins traffic from shared platform ALB"
    from_port       = 8080
    to_port         = 8080
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

  iam_instance_profile = aws_iam_instance_profile.jenkins.name

  user_data                   = file("${path.module}/jenkins_userdata.sh")
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
    Name    = "${var.project_name}-jenkins"
    Project = var.project_name
    Role    = "jenkins"
  }
}


# ============================================================
# JENKINS TARGET GROUP
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
# ATTACH JENKINS TO TARGET GROUP
# ============================================================

resource "aws_lb_target_group_attachment" "jenkins" {
  target_group_arn = aws_lb_target_group.jenkins.arn
  target_id        = aws_instance.jenkins.id
  port             = 8080
}