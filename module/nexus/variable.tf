variable "project_name" {
  description = "Project name used for naming and tagging"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_id" {
  description = "Subnet for the Nexus EC2 instance"
  type        = string
}

variable "key_name" {
  description = "EC2 key pair name"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for Nexus"
  type        = string
  default     = "t3.medium"
}

variable "platform_alb_security_group_id" {
  description = "Security group ID of the shared platform ALB"
  type        = string
}