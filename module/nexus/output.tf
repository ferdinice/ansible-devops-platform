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

output "target_group_arn" {
  description = "Nexus target group ARN"
  value       = aws_lb_target_group.nexus.arn
}