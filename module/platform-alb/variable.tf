variable "project_name" {
  description = "Project name used for naming and tagging"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet IDs for the shared platform ALB"
  type        = list(string)
}

variable "domain_name" {
  description = "Base Route53 domain"
  type        = string
}