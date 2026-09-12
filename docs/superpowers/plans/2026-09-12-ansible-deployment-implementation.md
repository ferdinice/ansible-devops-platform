# Ansible Deployment Implementation Plan

**Goal:** Configure Stage and Production EC2 instances with Ansible and deploy immutable Pet Adoption Docker images from Nexus.

**Architecture:** Jenkins orchestrates CI/CD and uses AWS SSM Run Command to trigger the dedicated Ansible controller. The controller uses AWS dynamic inventory to configure and deploy to private Stage and Production instances.

**Tech Stack:** Ansible, Docker, AWS EC2, AWS SSM, Nexus, Jenkins, SonarQube

**Spec:** docs/superpowers/specs/2026-09-12-ansible-deployment-design.md

## Global Constraints

- Stage and Production remain private.
- No hardcoded EC2 IP addresses.
- No hardcoded credentials.
- Nexus credentials use AWS SSM Parameter Store.
- Immutable Docker image tags only.
- Production uses the exact image tested in Stage.
- Rollback redeploys a previous image; it never rebuilds.

---

## Task 1 — Common Role

Create:

module/ansible/roles/common/tasks/main.yml

Responsibilities:

- update apt cache
- install required base packages
- ensure consistent baseline configuration
- remain idempotent

Validation:

ansible-playbook --syntax-check

Commit:

feat: add Ansible common role

---

## Task 2 — Docker Role

Create:

module/ansible/roles/docker/tasks/main.yml

Responsibilities:

- install Docker from the official Docker repository
- install required Docker packages
- enable Docker
- start Docker
- add ubuntu user to docker group
- remain idempotent

Validation:

docker --version
systemctl is-active docker

Commit:

feat: add Ansible Docker role

---

## Task 3 — Configure Playbook

Create:

module/ansible/playbooks/configure.yml

Responsibilities:

- target Stage or Production
- apply common role
- apply docker role

Validation:

ansible-playbook --syntax-check
ansible-playbook configure.yml --limit stage
ansible-playbook configure.yml --limit prod

Commit:

feat: add managed node configuration playbook

---

## Task 4 — Nexus Docker Registry

Terraform/Nexus changes will expose:

registry.ferdeve.fit

through the existing shared ALB using HTTPS.

Nexus will host the pet-adoption Docker repository.

Credentials will be stored in AWS SSM Parameter Store.

Commit:

feat: add secure Nexus Docker registry

---

## Task 5 — App Role

Create:

module/ansible/roles/app/tasks/main.yml

Responsibilities:

- obtain Nexus credentials securely
- authenticate to registry.ferdeve.fit
- pull exact immutable image tag
- stop/replace previous application container
- expose application on port 8080
- verify application health

Image format:

registry.ferdeve.fit/pet-adoption:<image_tag>

Commit:

feat: add immutable application deployment role

---

## Task 6 — Deploy Playbook

Create:

module/ansible/playbooks/deploy.yml

Inputs:

target_env
image_tag

Examples:

target_env=stage
image_tag=build-42

Deployment must fail if image_tag is missing.

Commit:

feat: add application deployment playbook

---

## Task 7 — Rollback Playbook

Create:

module/ansible/playbooks/rollback.yml

Inputs:

target_env
image_tag

Rollback redeploys a known-good existing Nexus image.

No Maven build.
No Docker build.

Commit:

feat: add immutable deployment rollback

---

## Task 8 — Jenkins to Ansible via SSM

Jenkins IAM receives least-privilege permission to:

- send SSM command to Ansible controller
- read command execution status

Jenkins must not SSH to Ansible.

Commit:

feat: allow Jenkins to trigger Ansible through SSM

---

## Task 9 — Jenkins CI/CD Pipeline

Pipeline flow:

Checkout
→ Maven tests/build
→ SonarQube analysis
→ Quality Gate
→ Docker build
→ immutable image tag
→ Nexus push
→ Stage deployment through SSM
→ Stage validation
→ Manual approval
→ Production deployment through SSM

Production receives the same image tag tested in Stage.

Commit:

feat: add end-to-end CI/CD pipeline

---

## Task 10 — Final Hardening

After application health is proven stable:

- change Stage ASG health_check_type from EC2 to ELB
- change Prod ASG health_check_type from EC2 to ELB
- verify ALB health checks
- verify rollback
- verify fresh Terraform destroy/apply workflow
- document interview architecture

Commit:

chore: harden deployment platform
