variable "aws_region" {
  description = "AWS region used to deploy the platform"
  type        = string
  default     = "eu-west-3"
}

variable "aws_profile" {
  description = "AWS CLI profile used by Terraform"
  type        = string
  default     = "personal-devops"
}

variable "project_name" {
  description = "Name used for platform resources"
  type        = string
  default     = "ansible-devops-platform"
}

variable "vpc_cidr" {
  description = "CIDR block for the platform VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR block for the public subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR block for the private subnet"
  type        = string
  default     = "10.0.2.0/24"
}

variable "availability_zone" {
  description = "Availability zone used by the initial deployment"
  type        = string
  default     = "eu-west-3a"
}

variable "allowed_cidr" {
  description = "CIDR allowed to access management services"
  type        = string
}

variable "public_subnet_2_cidr" {
  description = "CIDR block for the second public subnet"
  type        = string
  default     = "10.0.3.0/24"
}

variable "private_subnet_2_cidr" {
  description = "CIDR block for the second private subnet"
  type        = string
  default     = "10.0.4.0/24"
}

variable "availability_zone_2" {
  description = "Second availability zone"
  type        = string
  default     = "eu-west-3b"
}