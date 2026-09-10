# ============================================================
# ANSIBLE CONTROLLER MODULE
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
# ANSIBLE SECURITY GROUP
# ============================================================

resource "aws_security_group" "ansible" {
  name        = "${var.project_name}-ansible-sg"
  description = "Security group for Ansible controller"
  vpc_id      = var.vpc_id

  # No inbound SSH from the internet.
  # Administration is through AWS Systems Manager.

  egress {
    description = "Allow outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-ansible-sg"
    Project = var.project_name
  }
}


# ============================================================
# ANSIBLE IAM ROLE
# ============================================================

resource "aws_iam_role" "ansible" {
  name = "${var.project_name}-ansible-role"

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
    Name    = "${var.project_name}-ansible-role"
    Project = var.project_name
  }
}


# ============================================================
# SSM PERMISSION
# ============================================================

resource "aws_iam_role_policy_attachment" "ansible_ssm" {
  role       = aws_iam_role.ansible.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}


# ============================================================
# READ-ONLY EC2 DISCOVERY PERMISSION
# Used by Ansible dynamic inventory
# ============================================================

resource "aws_iam_role_policy" "ansible_ec2_discovery" {
  name = "${var.project_name}-ansible-ec2-discovery"
  role = aws_iam_role.ansible.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "ec2:DescribeInstances",
          "ec2:DescribeTags",
          "ec2:DescribeRegions",
          "ec2:DescribeAvailabilityZones"
        ]

        Resource = "*"
      }
    ]
  })
}


# ============================================================
# INSTANCE PROFILE
# ============================================================

resource "aws_iam_instance_profile" "ansible" {
  name = "${var.project_name}-ansible-profile"
  role = aws_iam_role.ansible.name

  tags = {
    Name    = "${var.project_name}-ansible-profile"
    Project = var.project_name
  }
}


# ============================================================
# ANSIBLE CONTROLLER EC2
# ============================================================

resource "aws_instance" "ansible" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = var.instance_type

  subnet_id              = var.subnet_id
  vpc_security_group_ids = [aws_security_group.ansible.id]

  associate_public_ip_address = true

  iam_instance_profile = aws_iam_instance_profile.ansible.name

  user_data                   = file("${path.module}/ansible_userdata.sh")
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
    Name        = "${var.project_name}-ansible-controller"
    Project     = var.project_name
    Role        = "ansible"
    Environment = "management"
  }
}

resource "aws_iam_role_policy" "ansible_parameter_access" {
  name = "${var.project_name}-ansible-parameter-access"
  role = aws_iam_role.ansible.id

  policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Action = [
          "ssm:GetParameter"
        ]

      Resource = var.ssh_private_key_parameter_arn }
    ]
  })
}