variable "project_name" {
  type = string
}

variable "vpc_id" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "ansible_security_group_id" {
  type = string
}

variable "platform_alb_security_group_id" {
  type = string
}

variable "instance_type" {
  type    = string
  default = "t3.micro"
}

variable "key_name" {
  description = "EC2 key pair used by Ansible for SSH"
  type        = string
}