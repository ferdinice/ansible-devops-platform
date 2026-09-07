output "vpc_id" {
  description = "ID of the platform VPC"
  value       = module.vpc.vpc_id
}

output "public_subnet_id" {
  description = "ID of the public subnet"
  value       = module.vpc.public_subnet_id
}

output "private_subnet_id" {
  description = "ID of the private subnet"
  value       = module.vpc.private_subnet_id
}

output "jenkins_public_ip" {
  description = "Public IP address of the Jenkins server"
  value       = module.jenkins.jenkins_public_ip
}

output "jenkins_public_dns" {
  description = "Public DNS name of the Jenkins server"
  value       = module.jenkins.jenkins_public_dns
}

output "jenkins_url" {
  description = "Jenkins web interface"
  value       = "http://${module.jenkins.jenkins_public_ip}:8080"
}