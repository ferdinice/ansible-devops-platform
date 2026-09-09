# ============================================================
# STAGE ENVIRONMENT
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
# STAGE SECURITY GROUP
# ============================================================

resource "aws_security_group" "stage" {
  name        = "${var.project_name}-stage-sg"
  description = "Security group for stage application nodes"
  vpc_id      = var.vpc_id

  ingress {
    description     = "SSH from Ansible controller"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [var.ansible_security_group_id]
  }

  ingress {
    description     = "Application traffic from shared ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [var.platform_alb_security_group_id]
  }

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project_name}-stage-sg"
    Project     = var.project_name
    Environment = "stage"
  }
}


# ============================================================
# IAM ROLE / SSM
# ============================================================

resource "aws_iam_role" "stage" {
  name = "${var.project_name}-stage-role"

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
}

resource "aws_iam_role_policy_attachment" "stage_ssm" {
  role       = aws_iam_role.stage.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "stage" {
  name = "${var.project_name}-stage-profile"
  role = aws_iam_role.stage.name
}


# ============================================================
# LAUNCH TEMPLATE
# ============================================================

resource "aws_launch_template" "stage" {
  name_prefix   = "${var.project_name}-stage-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = var.key_name

  iam_instance_profile {
    name = aws_iam_instance_profile.stage.name
  }

  vpc_security_group_ids = [
    aws_security_group.stage.id
  ]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -e

    hostnamectl set-hostname stage-node

    apt-get update -y
    apt-get install -y python3

    echo "Stage node bootstrap complete."
  EOF
  )

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  block_device_mappings {
    device_name = "/dev/sda1"

    ebs {
      volume_size           = 20
      volume_type           = "gp3"
      encrypted             = true
      delete_on_termination = true
    }
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name        = "${var.project_name}-stage"
      Project     = var.project_name
      Role        = "application"
      Environment = "stage"
    }
  }
}


# ============================================================
# TARGET GROUP
# ============================================================

resource "aws_lb_target_group" "stage" {
  name     = "${var.project_name}-stage-tg"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    path                = "/"
    protocol            = "HTTP"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
    matcher             = "200-399"
  }

  tags = {
    Name        = "${var.project_name}-stage-tg"
    Project     = var.project_name
    Environment = "stage"
  }
}


# ============================================================
# AUTO SCALING GROUP
# ============================================================

resource "aws_autoscaling_group" "stage" {
  name = "${var.project_name}-stage-asg"

  min_size         = 1
  max_size         = 2
  desired_capacity = 1

  vpc_zone_identifier = var.private_subnet_ids

  target_group_arns = [
    aws_lb_target_group.stage.arn
  ]

  health_check_type         = "EC2"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.stage.id
    version = "$Latest"
  }

  tag {
    key                 = "Project"
    value               = var.project_name
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = "stage"
    propagate_at_launch = true
  }
}


# ============================================================
# AUTO SCALING POLICY
# ============================================================

resource "aws_autoscaling_policy" "stage_cpu" {
  name                   = "${var.project_name}-stage-cpu-scaling"
  autoscaling_group_name = aws_autoscaling_group.stage.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 70
  }
}