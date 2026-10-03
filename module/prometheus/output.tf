output "prometheus_instance_id" {
  description = "Prometheus EC2 instance ID"
  value       = aws_instance.prometheus.id
}

output "prometheus_private_ip" {
  description = "Prometheus private IP"
  value       = aws_instance.prometheus.private_ip
}

output "prometheus_public_ip" {
  description = "Prometheus public IP"
  value       = aws_instance.prometheus.public_ip
}

output "target_group_arn" {
  description = "Prometheus target group ARN"
  value       = aws_lb_target_group.prometheus.arn
}
output "security_group_id" {
  description = "Security group ID of the Prometheus instance"
  value       = aws_security_group.prometheus.id
}