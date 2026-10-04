output "grafana_instance_id" {
  description = "Grafana EC2 instance ID"
  value       = aws_instance.grafana.id
}

output "grafana_private_ip" {
  description = "Grafana private IP"
  value       = aws_instance.grafana.private_ip
}

output "grafana_public_ip" {
  description = "Grafana public IP"
  value       = aws_instance.grafana.public_ip
}

output "target_group_arn" {
  description = "Grafana target group ARN"
  value       = aws_lb_target_group.grafana.arn
}

output "security_group_id" {
  description = "Security group ID of the Grafana instance"
  value       = aws_security_group.grafana.id
}
