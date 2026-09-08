output "sonarqube_instance_id" {
  description = "SonarQube EC2 instance ID"
  value       = aws_instance.sonarqube.id
}

output "sonarqube_private_ip" {
  description = "SonarQube private IP"
  value       = aws_instance.sonarqube.private_ip
}

output "sonarqube_public_ip" {
  description = "SonarQube public IP"
  value       = aws_instance.sonarqube.public_ip
}

output "target_group_arn" {
  description = "SonarQube target group ARN"
  value       = aws_lb_target_group.sonarqube.arn
}