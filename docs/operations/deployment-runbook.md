# Deployment Runbook — Ansible Enterprise DevOps Platform

**Project:** `ferdinice/ansible-devops-platform`  
**Application:** `ferdinice/pet-adoption-devops`, branch `feature/ansible-nexus-pipeline`, pipeline `Jenkinsfile.ansible`  
**AWS region:** `eu-west-3`  
**Status:** Historical live deployment verified; infrastructure subsequently destroyed (108 Terraform resources). This is a rebuild/deployment procedure, **not evidence that the services are currently online**.

## 1. Delivery architecture

GitHub → Jenkins → Maven build and tests → SonarQube analysis and quality gate → OWASP Dependency Check → Docker build → Nexus registry → AWS SSM Run Command → Ansible controller → staging → manual Jenkins approval → production.

Terraform provisions the project VPC, public/private subnets, NAT, ALB, Route 53 service records, EC2 service instances, dedicated Ansible controller, staging and production Auto Scaling Groups, IAM and SSM integrations. Prometheus and Grafana monitor the application nodes. Kubernetes/KOps is a **different enterprise project** and is not a deployment target here.

## 2. Preconditions for rebuilding

- Authorised access to the intended AWS account and `eu-west-3`; identify account using `aws sts get-caller-identity --profile personal-devops`.
- Infrastructure repository checked out at a reviewed commit (`ee9b7dc` was the last clean checkpoint before documentation cleanup; update this field after committing new documentation).
- A working Terraform S3 backend, bucket `ansible-devops-platform-tfstate-740994137090`, key `platform/terraform.tfstate`, and backend lockfile access.
- Verified DNS zone ownership for `ferdeve.fit`, including preservation of the existing ACM DNS-validation CNAME (deliberately removed from Terraform state before teardown).
- Valid AWS SSM SecureString parameters, service credentials and SSH key provisioning, or a documented replacement/restore approach. Destruction removed a Terraform-managed private-key SSM parameter and key pair.
- Backup inventory and EBS snapshots are available if preserving former service configuration is necessary. **A plain `terraform apply` does not mount or restore those snapshots.** Follow `disaster-recovery.md` if recovering former service state.

## 3. Provision and validate infrastructure

From the infrastructure repository:

```bash
terraform init
terraform fmt -check -recursive
terraform validate
terraform plan -out=tfplan
terraform show tfplan
```

Carefully review every planned resource, existing Route 53 names, permissions, costs and whether this is **fresh provisioning** or **restoration**. Only then, with operator approval:

```bash
terraform apply tfplan
terraform output
```

**Caution:** the project was destroyed and the original ACM DNS validation record was detached from Terraform state. A new plan may attempt to recreate an already-existing record. Review and reconcile it instead of blindly overwriting DNS. Never apply a stale plan. Recovered state snapshots are historical reference, **not** a current state file to push back over the empty backend.

## 4. Check platform readiness

Confirm EC2/ASGs, SSM agent connectivity, ALB target health, DNS and TLS, Jenkins, Nexus Docker registry, SonarQube, the dedicated Ansible controller, and staging/production nodes. The controller generates `/opt/ansible/inventory/aws_ec2.yml` on boot with `amazon.aws.aws_ec2`; it filters Project=`ansible-devops-platform` and groups hosts by `ec2_tags.Environment`. Its global `/etc/ansible/ansible.cfg` sets that inventory location. **Do not use empty `inventories/*/hosts.ini` paths or assume a checked-in static inventory exists.**

On the Ansible controller, after restoring SSM/SSH access:

```bash
sudo -iu ubuntu ansible-inventory --graph
```

Verify stage and prod groups before touching nodes. The configuration playbook is `module/ansible/playbooks/configure.yml` (roles: `common`, `docker`, `monitoring`); the deployment playbook is `module/ansible/playbooks/deploy.yml` (role: `app`).

## 5. Trigger and supervise Jenkins release

Configure Jenkins to read `Jenkinsfile.ansible` from the application repository's intended branch. Verify its webhook/trigger, credentials, NVD API key, SonarQube quality-gate integration and IAM/SSM permissions before building.

The pipeline generates a tagged image such as:

```text
registry.ferdeve.fit/pet-adoption-docker:build-7-37f911b
```

The exact registry/repository string matters. The Jenkins build sequence includes Maven test/verification, SonarQube, quality gate, OWASP Dependency Check, image build, Nexus push and registry manifest verification. It then uses SSM Run Command to execute both Ansible playbooks for `target_env=stage`, supplying `app_image_tag`.

Only approve the **manual production gate** after staging has passed health checks and production prerequisites are acceptable. The production stage overrides `DEPLOY_ENVIRONMENT=prod` and uses **the identical image tag**, not a rebuilt image.

## 6. Verify both environments

```bash
for host in stage.ferdeve.fit prod.ferdeve.fit; do
  echo "=== $host ==="
  curl -fsS "https://$host/actuator/health"
  echo
done
```

Both returned HTTP 200 and `{"status":"UP"}` in the October 2026 live test. After a new build, also verify the target EC2's actual Docker image using SSM:

```bash
sudo docker inspect pet-adoption --format '{{.Config.Image}}'
sudo docker ps --filter name=pet-adoption
```

Confirm Node Exporter is active, Prometheus targets show `UP` and Grafana charts collect staging/production metrics. Keep release ID, Git SHA, Jenkins build number, Ansible logs and change approval together in the release record.

## 7. Stop criteria and troubleshooting

Do not approve production if staging tests, SonarQube quality gate, Nexus push, container health or dynamic inventory identification fail. Inspect Jenkins build logs, SSM command invocation stdout/stderr, Ansible `PLAY RECAP`, EC2/cloud-init logs and ALB target health. A transient health retry during container warm-up is not a deployment failure if the playbook ends with `failed=0` and independent health checks pass.

**Known issue:** the `amazon.aws` collection emitted a deprecation warning for the `tags` host variable; the inventory generation code already uses `ec2_tags.Environment`. This was nonfatal and should be revisited during dependency updates, not blindly suppressed.

## 8. Scope and evidence

Historical evidence: Jenkins Build #7 completed manual production promotion; staging and production returned HTTP 200 over HTTPS; Prometheus targets and Grafana metrics were validated. After the later Terraform destroy, the running endpoints ceased to be a valid availability guarantee.

Related: [`rollback-runbook.md`](rollback-runbook.md), [`disaster-recovery.md`](disaster-recovery.md), and main technical documentation.
