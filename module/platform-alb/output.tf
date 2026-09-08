output "security_group_id" {
  description = "Security group ID of the shared platform ALB"
  value       = aws_security_group.platform_alb.id
}

output "listener_arn" {
  description = "HTTPS listener ARN"
  value       = aws_lb_listener.https.arn
}

output "alb_dns_name" {
  description = "DNS name of the shared platform ALB"
  value       = aws_lb.platform.dns_name
}

output "alb_zone_id" {
  description = "Route53 zone ID of the shared platform ALB"
  value       = aws_lb.platform.zone_id
}

output "hosted_zone_id" {
  description = "Route53 hosted zone ID"
  value       = data.aws_route53_zone.main.zone_id
}