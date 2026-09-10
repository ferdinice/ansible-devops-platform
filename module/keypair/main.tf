resource "tls_private_key" "platform" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "platform" {
  key_name   = "${var.project_name}-key"
  public_key = tls_private_key.platform.public_key_openssh

  tags = {
    Name    = "${var.project_name}-key"
    Project = var.project_name
  }
}

resource "local_sensitive_file" "private_key" {
  content         = tls_private_key.platform.private_key_pem
  filename        = "${path.root}/${var.project_name}-key.pem"
  file_permission = "0600"
}

# ============================================================
# STORE PRIVATE KEY IN SSM PARAMETER STORE
# ============================================================

resource "aws_ssm_parameter" "private_key" {
  name        = "/devops-platform/ssh/private-key"
  description = "SSH private key for Ansible managed nodes"
  type        = "SecureString"

  value = tls_private_key.platform.private_key_pem

  tags = {
    Name    = "${var.project_name}-ansible-private-key"
    Project = var.project_name
  }
}