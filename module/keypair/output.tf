output "key_name" {
  description = "Name of the AWS EC2 key pair"
  value       = aws_key_pair.platform.key_name
}

output "private_key_path" {
  description = "Local path of the generated private key"
  value       = local_sensitive_file.private_key.filename
  sensitive   = true
}