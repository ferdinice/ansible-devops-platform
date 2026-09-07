variable "project_name" {
  description = "Project name used for tagging"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID where Jenkins will be deployed"
  type        = string
}

variable "subnet_id" {
  description = "Public subnet ID for Jenkins"
  type        = string
}

variable "key_name" {
  description = "AWS EC2 key pair name"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for Jenkins"
  type        = string
  default     = "t3.medium"
}

variable "allowed_cidr" {
  description = "CIDR allowed to access Jenkins and SSH"
  type        = string
}

variable "domain_name" {
  description = "Base Route53 domain"
  type        = string
}

variable "jenkins_subdomain" {
  description = "Subdomain for Jenkins"
  type        = string
  default     = "jenkins"
}

variable "alb_subnet_ids" {
  description = "Public subnet IDs for the Jenkins Application Load Balancer"
  type        = list(string)
}