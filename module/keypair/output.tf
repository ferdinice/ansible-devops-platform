output "key_name" {
  description = "Name of the AWS EC2 key pair"
  value       = aws_key_pair.platform.key_name
}

output "private_key_path" {
  description = "Local path of the generated private key"
  value       = local_sensitive_file.private_key.filename
  sensitive   = true
}

output "private_key_parameter_arn" {
  description = "ARN of the SSM parameter containing the Ansible SSH private key"
  value       = aws_ssm_parameter.private_key.arn
}