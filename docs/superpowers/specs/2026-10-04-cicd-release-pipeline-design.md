# CI/CD Release Pipeline Design

## 1. Purpose

This design defines the CI/CD release architecture for the
ansible-devops-platform project.

The objective is to provide an automated and auditable delivery path for
the Pet Adoption application from source control through testing, code
quality analysis, artifact creation, staging deployment, production
approval, production deployment, monitoring, and rollback.

Application repository:

https://github.com/ferdinice/pet-adoption-devops

Infrastructure repository:

https://github.com/ferdinice/ansible-devops-platform

---

## 2. Architecture

The release path is:

GitHub
→ Jenkins
→ Maven Build and Test
→ SonarQube Analysis
→ SonarQube Quality Gate
→ Docker Image Build
→ Nexus Docker Registry
→ Ansible Stage Deployment
→ Stage Health Verification
→ Manual Production Approval
→ Ansible Production Deployment
→ Production Health Verification

Prometheus and Grafana provide infrastructure observability independently
of the release pipeline.

---

## 3. Source Control

The Pet Adoption application repository is the source of application code.

Jenkins checks out a specific Git commit for each build.

The Git commit SHA and Jenkins build number are used to identify the
resulting release artifact.

The infrastructure repository contains Terraform, Ansible, monitoring,
and deployment automation.

---

## 4. Continuous Integration

Jenkins is the CI/CD orchestrator.

For each application build Jenkins performs:

1. Source checkout.
2. Maven build.
3. Automated tests.
4. SonarQube static analysis.
5. SonarQube Quality Gate verification.
6. Docker image creation.
7. Docker image publication to Nexus.

A failed build, test, SonarQube analysis, or Quality Gate prevents
deployment.

---

## 5. Immutable Docker Images

Each successful pipeline creates an immutable Docker image.

The image tag follows:

build-<BUILD_NUMBER>-<GIT_SHA>

Example:

build-42-a1b2c3d

The same image that passes CI is promoted through staging and production.

Images are not rebuilt between environments.

The `latest` tag is not used as the deployment identity.

---

## 6. Nexus Artifact Repository

Nexus is the private Docker registry for release artifacts.

Jenkins has write access required to publish images.

Deployment systems use read access required to pull images.

Credentials must not be committed to Git.

The immutable image tag provides traceability between:

- Git commit
- Jenkins build
- Docker image
- staging deployment
- production deployment
- rollback release

---

## 7. Stage Deployment

After a successful image publication, Jenkins invokes Ansible to deploy
the immutable image to the staging environment.

The deployment supplies:

- `target_env=stage`
- `app_image_tag=<immutable image tag>`

Ansible performs the deployment using the application role.

Jenkins then verifies that the staging application is healthy.

A failed staging deployment or health verification stops the pipeline.

Production deployment is not offered until staging verification succeeds.

---

## 8. Production Approval

Production promotion requires an explicit manual approval in Jenkins.

The approval occurs only after:

- Maven build succeeds.
- Tests succeed.
- SonarQube analysis succeeds.
- Quality Gate passes.
- Docker image is published successfully.
- Staging deployment succeeds.
- Staging health verification succeeds.

This prevents every successful source commit from automatically becoming
a production release.

---

## 9. Production Deployment

After approval, Jenkins invokes Ansible with:

- `target_env=prod`
- the exact immutable image tag already tested in staging.

No production image rebuild occurs.

After deployment Jenkins verifies the production application health.

The pipeline fails if production health verification fails.

---

## 10. Rollback

Rollback uses a previously published immutable Nexus image.

The rollback operator identifies a known-good image tag and invokes:

`module/ansible/playbooks/rollback.yml`

Required values include:

- target environment
- previous immutable `app_image_tag`

The rollback playbook validates that an image tag has been supplied and
then uses the same application deployment role used by normal releases.

Rollback therefore redeploys a known artifact rather than rebuilding old
source code.

---

## 11. Infrastructure Automation

Terraform provisions the AWS infrastructure.

Major platform components include:

- VPC networking
- public and private subnets
- Application Load Balancer
- Route53 DNS
- HTTPS routing
- Jenkins
- SonarQube
- Nexus
- Ansible controller
- stage application infrastructure
- production application infrastructure
- Prometheus
- Grafana

Infrastructure changes remain separate from application release artifacts.

---

## 12. Configuration Management

Ansible configures managed application nodes and performs application
deployment.

Dynamic AWS EC2 discovery identifies managed stage and production nodes.

Administrative automation uses AWS Systems Manager rather than requiring
a traditional bastion-host workflow.

---

## 13. Security

The platform follows these controls:

- No application or infrastructure passwords are committed to Git.
- CI/CD credentials are provided through controlled credential stores.
- AWS Systems Manager is used for administrative access where applicable.
- Security-group-to-security-group rules restrict internal service traffic.
- Application nodes are not directly exposed for administrative SSH.
- Production deployment requires manual approval.
- Immutable image tags prevent ambiguous releases.

---

## 14. Observability

Node Exporter exposes operating-system metrics from managed application
nodes.

Prometheus uses AWS EC2 service discovery to discover stage and production
targets.

Grafana uses Prometheus as its provisioned datasource.

The provisioned infrastructure dashboard includes:

- stage node availability
- production node availability
- CPU utilisation
- memory utilisation
- root filesystem utilisation
- network receive throughput

This provides visibility into the infrastructure independently of Jenkins.

---

## 15. Failure Behaviour

The pipeline follows fail-fast behaviour.

If build or tests fail:

No Docker image is released.

If SonarQube or the Quality Gate fails:

No deployment occurs.

If Nexus publication fails:

No deployment occurs.

If staging deployment fails:

Production promotion is blocked.

If staging health verification fails:

Production promotion is blocked.

If production deployment or health verification fails:

The pipeline reports failure and a known-good immutable image can be
redeployed through the rollback process.

---

## 16. Release Traceability

A production release can be traced through:

Git commit
→ Jenkins build number
→ immutable Docker image
→ Nexus artifact
→ Ansible deployment
→ environment

This provides a clear audit trail for deployments and rollback.

---

## 17. Final Delivery Model

The completed platform demonstrates:

- Infrastructure as Code with Terraform
- Configuration Management with Ansible
- CI/CD orchestration with Jenkins
- automated testing with Maven
- static analysis and quality gates with SonarQube
- private artifact management with Nexus
- immutable Docker releases
- staged promotion
- manual production approval
- automated health verification
- rollback using known-good artifacts
- monitoring with Prometheus
- visualization with Grafana
- AWS Systems Manager administration

The platform is intended to demonstrate an end-to-end DevOps delivery
workflow rather than a collection of disconnected tools.
