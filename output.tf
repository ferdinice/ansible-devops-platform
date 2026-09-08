output "jenkins_url" {
  description = "Secure Jenkins URL"
  value       = "https://jenkins.ferdeve.fit"
}

output "nexus_url" {
  description = "Secure Nexus URL"
  value       = "https://nexus.ferdeve.fit"
}

output "jenkins_public_ip" {
  description = "Jenkins public IP"
  value       = module.jenkins.jenkins_public_ip
}

output "jenkins_public_dns" {
  description = "Jenkins public DNS"
  value       = module.jenkins.jenkins_public_dns
}

output "nexus_instance_id" {
  description = "Nexus EC2 instance ID"
  value       = module.nexus.nexus_instance_id
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "public_subnet_id" {
  value = module.vpc.public_subnet_id
}

output "private_subnet_id" {
  value = module.vpc.private_subnet_id
}