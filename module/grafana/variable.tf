variable "project_name" {
  description = "Project name used for naming and tagging"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_id" {
  description = "Subnet for the Grafana EC2 instance"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for Grafana"
  type        = string
  default     = "t3.micro"
}

variable "platform_alb_security_group_id" {
  description = "Security group ID of the shared platform ALB"
  type        = string
}

variable "prometheus_private_ip" {
  description = "Private IP address of the Prometheus server"
  type        = string
}
