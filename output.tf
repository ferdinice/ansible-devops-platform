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

output "sonarqube_url" {
  description = "Secure SonarQube URL"
  value       = "https://sonarqube.ferdeve.fit"
}

output "sonarqube_instance_id" {
  description = "SonarQube EC2 instance ID"
  value       = module.sonarqube.sonarqube_instance_id
}

output "ansible_instance_id" {
  description = "Ansible controller EC2 instance ID"
  value       = module.ansible.ansible_instance_id
}

output "ansible_private_ip" {
  description = "Ansible controller private IP"
  value       = module.ansible.ansible_private_ip
}

output "stage_url" {
  description = "Stage application URL"
  value       = "https://stage.ferdeve.fit"
}

output "prod_url" {
  description = "Production application URL"
  value       = "https://prod.ferdeve.fit"
}

output "stage_asg_name" {
  description = "Stage Auto Scaling Group name"
  value       = module.stage_env.autoscaling_group_name
}

output "prod_asg_name" {
  description = "Production Auto Scaling Group name"
  value       = module.prod_env.autoscaling_group_name
}

output "jenkins_instance_id" {
  description = "Jenkins EC2 instance ID"
  value       = module.jenkins.jenkins_instance_id
}
output "prometheus_url" {
  description = "Secure Prometheus URL"
  value       = "https://prometheus.ferdeve.fit"
}

output "prometheus_instance_id" {
  description = "Prometheus EC2 instance ID"
  value       = module.prometheus.prometheus_instance_id
}

# ============================================================
# GRAFANA
# ============================================================

output "grafana_url" {
  description = "Secure Grafana URL"
  value       = "https://grafana.ferdeve.fit"
}

output "grafana_instance_id" {
  description = "Grafana EC2 instance ID"
  value       = module.grafana.grafana_instance_id
}
