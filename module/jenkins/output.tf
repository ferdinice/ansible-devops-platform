output "jenkins_instance_id" {
  value = aws_instance.jenkins.id
}

output "jenkins_public_ip" {
  value = aws_instance.jenkins.public_ip
}

output "jenkins_public_dns" {
  value = aws_instance.jenkins.public_dns
}

output "target_group_arn" {
  description = "Jenkins target group ARN"
  value       = aws_lb_target_group.jenkins.arn
}