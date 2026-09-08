output "nexus_instance_id" {
  description = "Nexus EC2 instance ID"
  value       = aws_instance.nexus.id
}

output "nexus_private_ip" {
  description = "Nexus private IP"
  value       = aws_instance.nexus.private_ip
}

output "nexus_public_ip" {
  description = "Nexus public IP"
  value       = aws_instance.nexus.public_ip
}

output "nexus_url" {
  description = "Secure Nexus URL"
  value       = "https://${var.nexus_subdomain}.${var.domain_name}"
}