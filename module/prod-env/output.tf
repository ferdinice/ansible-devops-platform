output "security_group_id" {
  value = aws_security_group.prod.id
}

output "target_group_arn" {
  value = aws_lb_target_group.prod.arn
}

output "autoscaling_group_name" {
  value = aws_autoscaling_group.prod.name
}