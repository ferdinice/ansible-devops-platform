variable "project_name" {
  description = "Project name used for naming and tagging"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "subnet_id" {
  description = "Subnet where the Ansible controller will be deployed"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for the Ansible controller"
  type        = string
  default     = "t3.micro"
}