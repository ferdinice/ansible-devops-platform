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

variable "ssh_private_key_parameter_arn" {
  description = "ARN of the SSM parameter containing the SSH private key"
  type        = string
}