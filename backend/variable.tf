variable "aws_region" {
  type    = string
  default = "eu-west-3"
}

variable "aws_profile" {
  type    = string
  default = "personal-devops"
}

variable "state_bucket_name" {
  type        = string
  description = "Globally unique S3 bucket name for Terraform remote state"
}