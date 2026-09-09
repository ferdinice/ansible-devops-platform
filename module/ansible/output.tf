output "ansible_instance_id" {
  description = "Ansible controller EC2 instance ID"
  value       = aws_instance.ansible.id
}

output "ansible_private_ip" {
  description = "Private IP of the Ansible controller"
  value       = aws_instance.ansible.private_ip
}

output "ansible_public_ip" {
  description = "Public IP of the Ansible controller"
  value       = aws_instance.ansible.public_ip
}

output "ansible_security_group_id" {
  description = "Security group ID of the Ansible controller"
  value       = aws_security_group.ansible.id
}