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

variable "allowed_cidr" {
  type = string
}

variable "platform_alb_security_group_id" {
  description = "Security group ID of the shared platform ALB"
  type        = string
}