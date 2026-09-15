# ============================================================
# NEXUS MODULE
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
# NEXUS SECURITY GROUP
# ============================================================

resource "aws_security_group" "nexus" {
  name        = "${var.project_name}-nexus-sg"
  description = "Allow Nexus traffic only from Nexus ALB"
  vpc_id      = var.vpc_id

  # Nexus UI/API can only be reached through the shared platform ALB.
  ingress {
    description     = "Nexus traffic from shared platform ALB"
    from_port       = 8081
    to_port         = 8081
    protocol        = "tcp"
    security_groups = [var.platform_alb_security_group_id]
  }

  # Docker registry connector can only be reached through the shared platform ALB.
  ingress {
    description     = "Nexus Docker registry traffic from shared platform ALB"
    from_port       = 8082
    to_port         = 8082
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
    Name    = "${var.project_name}-nexus-sg"
    Project = var.project_name
  }
}


# ============================================================
# NEXUS IAM ROLE
# ============================================================

resource "aws_iam_role" "nexus" {
  name = "${var.project_name}-nexus-role"

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
    Name    = "${var.project_name}-nexus-role"
    Project = var.project_name
  }
}


# ============================================================
# SSM PERMISSION
# ============================================================

resource "aws_iam_role_policy_attachment" "nexus_ssm" {
  role       = aws_iam_role.nexus.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}


# ============================================================
# NEXUS INSTANCE PROFILE
# ============================================================

resource "aws_iam_instance_profile" "nexus" {
  name = "${var.project_name}-nexus-profile"
  role = aws_iam_role.nexus.name

  tags = {
    Name    = "${var.project_name}-nexus-profile"
    Project = var.project_name
  }
}


# ============================================================
# NEXUS EC2 SERVER
# ============================================================

resource "aws_instance" "nexus" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.nexus.id]

  key_name = var.key_name

  associate_public_ip_address = true

  iam_instance_profile = aws_iam_instance_profile.nexus.name

  user_data = join("\n", [
    file("${path.module}/nexus_userdata.sh"),
    file("${path.module}/nexus_bootstrap.sh")
  ])
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
# NEXUS TARGET GROUP
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


# ============================================================
# ATTACH NEXUS TO TARGET GROUP
# ============================================================

resource "aws_lb_target_group_attachment" "nexus" {
  target_group_arn = aws_lb_target_group.nexus.arn
  target_id        = aws_instance.nexus.id
  port             = 8081
}

# ============================================================
# NEXUS DOCKER REGISTRY TARGET GROUP
# ============================================================

resource "aws_lb_target_group" "registry" {
  name     = "nexus-registry-tg"
  port     = 8082
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    enabled             = true
    path                = "/v2/"
    protocol            = "HTTP"
    port                = "traffic-port"
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    matcher             = "200,401,403"
  }

  tags = {
    Name    = "${var.project_name}-nexus-registry-tg"
    Project = var.project_name
  }
}


# ============================================================
# ATTACH NEXUS TO DOCKER REGISTRY TARGET GROUP
# ============================================================

resource "aws_lb_target_group_attachment" "registry" {
  target_group_arn = aws_lb_target_group.registry.arn
  target_id        = aws_instance.nexus.id
  port             = 8082
}

# ============================================================
# NEXUS REGISTRY CREDENTIAL BOOTSTRAP PERMISSIONS
# ============================================================

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

resource "aws_iam_role_policy" "nexus_registry_credentials" {
  name = "${var.project_name}-nexus-registry-credentials"
  role = aws_iam_role.nexus.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Sid    = "WriteRegistryCredentials"
        Effect = "Allow"

        Action = [
          "ssm:GetParameter",
          "ssm:PutParameter"
        ]

        Resource = [
          "arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter/devops-platform/nexus/ci-writer-password",
          "arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter/devops-platform/nexus/deploy-reader-password"
        ]
      }
    ]
  })
}