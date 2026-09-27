variable "project_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "subnet_id" {
  type = string
}

variable "key_name" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t3.medium"
}

variable "platform_alb_security_group_id" {
  description = "Security group ID of the shared platform ALB"
  type        = string
}

variable "ansible_instance_id" {
  description = "EC2 instance ID of the Ansible controller Jenkins may invoke through SSM"
  type        = string
}
