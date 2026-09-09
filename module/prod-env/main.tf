# ============================================================
# PROD ENVIRONMENT
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


resource "aws_security_group" "prod" {
  name        = "${var.project_name}-prod-sg"
  description = "Security group for production application nodes"
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
    Name        = "${var.project_name}-prod-sg"
    Project     = var.project_name
    Environment = "prod"
  }
}


resource "aws_iam_role" "prod" {
  name = "${var.project_name}-prod-role"

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

resource "aws_iam_role_policy_attachment" "prod_ssm" {
  role       = aws_iam_role.prod.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "prod" {
  name = "${var.project_name}-prod-profile"
  role = aws_iam_role.prod.name
}


resource "aws_launch_template" "prod" {
  name_prefix   = "${var.project_name}-prod-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = var.key_name

  iam_instance_profile {
    name = aws_iam_instance_profile.prod.name
  }

  vpc_security_group_ids = [
    aws_security_group.prod.id
  ]

  user_data = base64encode(<<-EOF
    #!/bin/bash
    set -e

    hostnamectl set-hostname prod-node

    apt-get update -y
    apt-get install -y python3

    echo "Production node bootstrap complete."
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
      Name        = "${var.project_name}-prod"
      Project     = var.project_name
      Role        = "application"
      Environment = "prod"
    }
  }
}


resource "aws_lb_target_group" "prod" {
  name     = "${var.project_name}-prod-tg"
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
    Name        = "${var.project_name}-prod-tg"
    Project     = var.project_name
    Environment = "prod"
  }
}


resource "aws_autoscaling_group" "prod" {
  name = "${var.project_name}-prod-asg"

  min_size         = 1
  max_size         = 3
  desired_capacity = 1

  vpc_zone_identifier = var.private_subnet_ids

  target_group_arns = [
    aws_lb_target_group.prod.arn
  ]

  health_check_type         = "EC2"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.prod.id
    version = "$Latest"
  }

  tag {
    key                 = "Project"
    value               = var.project_name
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = "prod"
    propagate_at_launch = true
  }
}


resource "aws_autoscaling_policy" "prod_cpu" {
  name                   = "${var.project_name}-prod-cpu-scaling"
  autoscaling_group_name = aws_autoscaling_group.prod.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }

    target_value = 70
  }
}