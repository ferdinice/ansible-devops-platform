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

variable "alb_subnet_ids" {
  description = "Public subnet IDs for the Nexus ALB"
  type        = list(string)
}

variable "key_name" {
  description = "EC2 key pair name"
  type        = string
}

variable "domain_name" {
  description = "Base Route53 domain"
  type        = string
}

variable "nexus_subdomain" {
  description = "Nexus DNS subdomain"
  type        = string
  default     = "nexus"
}

variable "instance_type" {
  description = "EC2 instance type for Nexus"
  type        = string
  default     = "t3.medium"
}