# Ansible Deployment Platform Design

## Goal

Build a secure CI/CD deployment platform using Jenkins, SonarQube, Nexus,
AWS Systems Manager, and Ansible to deploy the Pet Adoption application
to Stage and Production environments.

## Application

Application repository:

https://github.com/ferdinice/pet-adoption-devops

The application is a Spring Boot application built with Maven.

For the initial platform implementation, the application will use its
default H2 database configuration and run as a single Docker container.

The application will listen on port 8080.

## CI/CD Flow

Developer push
→ Jenkins
→ SonarQube analysis
→ Maven build
→ Docker image build
→ Nexus Docker registry
→ Ansible Stage deployment
→ Stage validation
→ Manual approval
→ Ansible Production deployment

## Build Once, Promote Same Artifact

Jenkins builds one immutable Docker image.

Example:

registry.ferdeve.fit/pet-adoption:build-42

The same image that successfully runs in Stage is promoted to Production.

Production must never rebuild the application.

## Nexus

Nexus has two responsibilities:

- Nexus UI:
  https://nexus.ferdeve.fit

- Docker Registry:
  https://registry.ferdeve.fit

The Docker registry is exposed through the existing shared Application
Load Balancer using HTTPS.

No Nexus IP address will be hardcoded.

## Secrets

Sensitive values will not be stored in Git.

AWS SSM Parameter Store SecureString parameters will hold:

- Nexus registry username
- Nexus registry password
- Ansible SSH private key

Jenkins and the Ansible controller will receive only the IAM permissions
required to retrieve the secrets they need.

## Jenkins

Jenkins is the CI/CD orchestrator.

Responsibilities:

- checkout source
- execute Maven build
- trigger SonarQube analysis
- enforce SonarQube quality gate
- build Docker image
- push Docker image to Nexus
- trigger Stage deployment
- validate Stage
- request manual Production approval
- trigger Production deployment

Jenkins will not SSH to the Ansible controller.

## Jenkins to Ansible Communication

Jenkins will trigger deployment commands using AWS Systems Manager
Run Command.

Flow:

Jenkins
→ AWS SSM Run Command
→ Ansible Controller
→ ansible-playbook
→ Stage or Production

The Ansible controller does not require inbound SSH access from Jenkins.

## Ansible Controller

The dedicated Ansible controller owns configuration management and
application deployment.

AWS EC2 dynamic inventory discovers instances using tags.

Stage and Production instances are contacted using their private IP
addresses.

## Ansible Roles

### common

Responsible for base operating system configuration and required
utilities.

### docker

Responsible for installing and configuring Docker and ensuring the
Docker service is running.

### app

Responsible for:

- authenticating to Nexus
- pulling the requested immutable image
- replacing the existing application container
- starting the requested release
- verifying application health

## Playbooks

### configure.yml

Applies the common and docker roles to managed nodes.

### deploy.yml

Deploys an explicitly supplied immutable image tag to the selected
environment.

Example:

image_tag=build-42

### rollback.yml

Redeploys a previously known-good immutable Nexus image tag.

Rollback does not rebuild the application.

Example:

image_tag=build-41

## Stage and Production

Stage and Production instances remain inside private subnets.

The shared Application Load Balancer routes:

stage.ferdeve.fit
→ Stage target group
→ application port 8080

prod.ferdeve.fit
→ Production target group
→ application port 8080

## Production Approval

Production deployment requires an explicit Jenkins manual approval.

The artifact is not rebuilt after approval.

The exact Docker image tested in Stage is deployed to Production.

## Rollback

Rollback selects a previous immutable Nexus image.

Example:

Current:
pet-adoption:build-42

Rollback:
pet-adoption:build-41

Ansible stops the current container, pulls or reuses build-41, launches
it, and verifies application health.

## Security Principles

- Jenkins has no public SSH access.
- Administrative access uses AWS Systems Manager.
- Stage and Production remain private.
- Application traffic reaches instances only through the shared ALB.
- Registry traffic uses HTTPS.
- Secrets are never committed to Git.
- No hardcoded EC2 IP addresses.
- IAM permissions follow least privilege.
- Immutable image tags are used for deployments.
