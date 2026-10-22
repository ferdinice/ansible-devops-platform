# Ansible Enterprise DevOps Platform

**Technical implementation, validation, operations and recovery documentation**  
**Status:** Successfully demonstrated, then intentionally destroyed to control AWS cost  
**AWS region:** `eu-west-3`  
**Infrastructure repository:** https://github.com/ferdinice/ansible-devops-platform (`main`, last confirmed commit `ee9b7dc`)  
**Application repository:** https://github.com/ferdinice/pet-adoption-devops (`feature/ansible-nexus-pipeline`, last confirmed commit `37f911b`)  
**Last live validation evidence:** 18–19 October 2026

> **Important:** This is the Ansible/EC2 enterprise project, not the separately built KOps/Kubernetes enterprise platform. The two must remain operationally distinct. Domain names below document previously validated endpoints; the Ansible infrastructure was later destroyed and those URLs are **not claimed to be currently live**.

## 1. Executive summary

The project demonstrates an automated, security-aware software delivery workflow for a Java Pet Adoption application. Terraform provisions an isolated AWS VPC and the platform's services; Jenkins runs automated build, quality and dependency checks; Docker packages the application; Nexus hosts immutable container images; and an Ansible controller configures and deploys the application to staging and, after manual approval, production. Prometheus and Grafana provide infrastructure observability. AWS Systems Manager (SSM) Run Command provides remote execution and operational verification.

A complete Jenkins Build #7 was observed to pass. Its deployed image, `registry.ferdeve.fit/pet-adoption-docker:build-7-37f911b`, passed local actuator health checks and external HTTPS health checks on staging and production. A controlled staging rollback to Build #6 succeeded and staging was restored to Build #7. The infrastructure was then backed up and intentionally destroyed using a reviewed 108-resource Terraform plan; `terraform state list | wc -l` returned `0` afterward.

## 2. Goals and boundaries

The demonstrated goals were infrastructure as code; reproducible server configuration; CI quality/security gates; immutable image promotion; staging-first deployment; manual production authorization; health verification; monitoring; and testable rollback. The environment was a portfolio/lab implementation rather than evidence of production SLAs or a formal disaster-recovery drill.

**In scope:** VPC/subnets, EC2, IAM/SSM, application load balancing, Route 53 records, ACM/TLS, Jenkins, Maven, SonarQube, OWASP Dependency-Check, Nexus, Ansible, Docker, Prometheus and Grafana.

**Out of scope:** KOps Kubernetes, Argo CD GitOps and the earlier Kubernetes project's AWS infrastructure. The projects use some related naming (including the `ferdeve.fit` DNS zone), which requires care when managing shared DNS and certificate-validation records.

## 3. Architecture and workflow

```text
GitHub application branch
        |
        v
      Jenkins
        |-- Checkout + version tag (build-N-gitsha)
        |-- Maven verify/tests + WAR artifact verification
        |-- SonarQube analysis -> quality gate
        |-- OWASP Dependency-Check
        |-- Docker image build
        |-- Nexus authentication -> image push -> registry-manifest verification
        |
        v
AWS SSM Run Command -> Ansible controller (AWS-tag discovery)
        |
        |-- configure.yml -> common -> docker -> monitoring roles
        |-- deploy.yml -> app role -> Docker image from Nexus -> HTTP health check
        v
     Staging EC2 behind AWS ALB + TLS
        |
        v
   Jenkins manual production approval
        |
        v
AWS SSM -> Ansible configure.yml and deploy.yml for prod
        |
        v
     Production EC2 behind AWS ALB + TLS

Prometheus <-- Node Exporter (stage and prod)
Grafana    --> Prometheus datasource / infrastructure dashboards
```

### Separation of responsibilities

| System | Responsibility |
|---|---|
| Terraform | Declare and manage AWS infrastructure resources |
| EC2 user-data | Bootstrap Jenkins/Ansible/other service hosts on initial creation |
| AWS IAM + SSM | Scoped credentials, parameter retrieval and managed remote execution |
| Jenkins | Coordinate CI gates and controlled CD stages |
| SonarQube | Static analysis and quality gate |
| OWASP Dependency-Check | Dependency vulnerability reporting |
| Nexus | Docker registry for immutable application artifacts |
| Ansible | Target discovery, reusable server configuration and application rollout |
| Docker | Run the versioned application container on each environment |
| ALB, ACM, Route 53 | HTTPS access and host-based routing |
| Prometheus and Grafana | Collect and visualize infrastructure telemetry |

## 4. Source code and important locations

### Infrastructure repository

| Repository location | Function |
|---|---|
| `provider.tf` | AWS provider and S3 Terraform backend configuration |
| `main.tf` | Root module orchestration, listener rules, service DNS records |
| `module/vpc/` | VPC, public/private subnets, route tables, internet/NAT gateway |
| `module/platform-alb/` | Application load balancer, listener, TLS/certificate wiring |
| `module/jenkins/` | Jenkins EC2, IAM, security group, target group |
| `module/nexus/` | Nexus EC2, registry routing, permissions |
| `module/sonarqube/` | SonarQube instance, IAM, listener/target-group integration |
| `module/ansible/` | Ansible controller and EC2 bootstrap script |
| `module/stage-env/`, `module/prod-env/` | Application environment launch templates, ASGs and target groups |
| `module/prometheus/`, `module/grafana/` | Monitoring service infrastructure |
| `module/keypair/` | SSH key generation and recovery via SSM parameter |
| `module/ansible/playbooks/` | Configuration, deployment and rollback orchestration |
| `module/ansible/roles/` | `common`, `docker`, `monitoring`, and `app` roles |

### Application repository

`Jenkinsfile.ansible` on `feature/ansible-nexus-pipeline` is the tested pipeline. Do not confuse it with another Jenkinsfile on a different branch.

## 5. AWS infrastructure design

**Region:** `eu-west-3` (Paris). The previously deployed Ansible VPC was `vpc-077f7d3c9c831c7ed`, CIDR `10.0.0.0/16`. The root Terraform configuration created multiple public/private subnets, an internet gateway, NAT gateway, route tables, security groups, IAM profiles, ALB and route rules. Staging and production application instances were represented in Auto Scaling Groups, separate from the infrastructure hosts.

The audited running infrastructure included eight EC2 instances: Jenkins, Nexus, SonarQube, Ansible controller, Prometheus, Grafana, staging and production. At the time of validation, staging had private IP `10.0.4.168` and production `10.0.2.48`. These are **historical** identifiers and will change after a normal rebuild.

The S3 Terraform backend used:

```hcl
backend "s3" {
  bucket       = "ansible-devops-platform-tfstate-740994137090"
  key          = "platform/terraform.tfstate"
  region       = "eu-west-3"
  profile      = "personal-devops"
  encrypt      = true
  use_lockfile = true
}
```

The project also used `ferdinice-devops-secure-backups-740994137090` to hold service archives. Terraform state and backup objects are sensitive; they should not enter the public repository.

### Network/security design notes

- The ALB used host-based routing for `jenkins`, `nexus`, `registry`, `sonarqube`, `prometheus`, `grafana`, `stage` and `prod` subdomains of `ferdeve.fit`.
- Staging and production were separate Ansible inventory groups and application environments.
- Ansible targeted instances filtered by `Project=ansible-devops-platform`, not the original Kubernetes cluster.
- An ACM certificate-validation CNAME was deliberately removed from Terraform **state management** (not deleted from Route 53) before destroying the rest of the Ansible platform because it might be relevant to certificates under the shared DNS zone.

## 6. Ansible controller and dynamic inventory

`module/ansible/ansible_userdata.sh` bootstraps an Ubuntu-based controller. It installs an isolated Python environment, AWS CLI, Ansible and the AWS/Docker collections. The verified source pins `ansible-core==2.21.4`, `amazon.aws==11.4.0` and `community.docker==5.3.0` in bootstrap commands.

The script generates `/opt/ansible/inventory/aws_ec2.yml` on the EC2 controller:

```yaml
plugin: amazon.aws.aws_ec2
regions:
  - eu-west-3
filters:
  tag:Project: ansible-devops-platform
  instance-state-name: running
hostnames:
  - private-ip-address
keyed_groups:
  - key: ec2_tags.Environment
    prefix: ""
    separator: ""
compose:
  ansible_host: private_ip_address
```

It also generates `/etc/ansible/ansible.cfg` with the dynamic inventory and roles path. The generated inventory is **not a versioned `aws_ec2.yml` within the repository**, which explains why searches of `module/ansible/inventories` did not find it.

During the rollback test, a separate ad hoc inspection command pointed at a nonexistent `inventories/stage/hosts.yml` and failed to parse inventory. This affected only that inspection command; the rollback playbook succeeded using the controller's configured dynamic inventory. Independent Docker inspection was then used to confirm the running image.

The AWS collection emitted a deprecation warning about the `tags` host variable; current source already uses `ec2_tags.Environment`. This warning was not observed to block deployment. Do not change working inventory blindly; evaluate it when dependency versions are updated.

## 7. Playbooks and roles

### Configuration (`module/ansible/playbooks/configure.yml`)

Targets `{{ target_env | default('stage') }}`, uses privilege escalation (`become: true`), gathers facts and runs roles in order:

1. `common`: OS package prerequisites.
2. `docker`: apt repository, packages, Docker service and group membership.
3. `monitoring`: installs and starts Prometheus Node Exporter.

### Deployment (`deploy.yml`)

Targets the requested environment and executes `app`. The app role validates the image tag, retrieves a Nexus deploy-reader password from encrypted SSM Parameter Store, authenticates to Nexus, pulls the requested image, runs `pet-adoption` with the configured port mapping, waits for TCP readiness, and performs an HTTP GET on `/actuator/health` expecting status `200`.

The role uses `community.docker.docker_container` with `state: started`, `restart_policy: unless-stopped`, `recreate: false`, and port `8080:8080`. Changing the image was observed to update the container during rollback and restoration; independent image inspection is nevertheless a necessary validation step.

### Rollback (`rollback.yml`)

The rollback playbook validates the explicitly supplied `app_image_tag` and reuses the `app` role. It does not select the previous image automatically; the operator must provide a known available, immutable tag. Successful playbook execution **alone** does not establish the version; verify by inspecting the running Docker container and checking health.

## 8. Jenkins pipeline and controlled promotion

The tested branch's `Jenkinsfile.ansible` defines the following sequence:

1. Checkout source; tag image `build-${BUILD_NUMBER}-${GIT_SHORT_SHA}`.
2. Maven `clean verify`.
3. SonarQube scan and timed quality gate.
4. OWASP Dependency-Check and report publication.
5. WAR artifact existence check.
6. Build Docker image.
7. Authenticate to Nexus using a password read from SSM Parameter Store.
8. Push immutable image and verify its manifest in Nexus.
9. Discover exactly one Ansible controller by AWS Project/Role/Environment tags.
10. Use AWS SSM Run Command to refresh Ansible repository and run `configure.yml` and `deploy.yml` against `stage`.
11. Require Jenkins `input` approval, restricted in code to Jenkins submitter `admin`.
12. Reuse the same image tag for `prod` and run the same Ansible playbooks via SSM.

The CD stage polls SSM invocation status and treats non-`Success` outcomes as pipeline failures. Staging and production deploy **the same build-tagged image**. Manual approval provides separation between automated staging and production promotion. This is a manual promotion gate, not an automatic canary strategy.

### Observed release

- Successful Jenkins Build: **#7**.
- Application image: `registry.ferdeve.fit/pet-adoption-docker:build-7-37f911b`.
- SSM and Ansible output confirmed configuration and deployment to both environments.
- Docker inspection in production confirmed the image and its running container.
- Production actuator returned `{"status":"UP"}`.
- Both previously live URLs, `https://stage.ferdeve.fit/actuator/health` and `https://prod.ferdeve.fit/actuator/health`, returned HTTP 200 during the validation session.

## 9. Monitoring and observability

Prometheus successfully reported three relevant targets as **UP** during validation:

| Target | Historical scrape endpoint | Observed status |
|---|---|---|
| Production Node Exporter | `10.0.2.48:9100` | UP |
| Staging Node Exporter | `10.0.4.168:9100` | UP |
| Prometheus | `localhost:9090` | UP |

Grafana displayed staging and production infrastructure CPU and memory readings. Disk and network panels were visible, although their underlying values were not fully inspected in the recorded walkthrough. Thus infrastructure metric collection was verified, but no blanket claim of application-level SLO monitoring or completed alert testing is made.

## 10. Rollback and restoration test evidence

The staging rollback was deliberately non-production:

| Step | Evidence |
|---|---|
| Initial version | Both environments: `build-7-37f911b` |
| Select older image | Staging had `build-6-176277f` locally |
| Execute rollback | SSM Ansible command succeeded, `failed=0` |
| Independently inspect | Staging Docker `Config.Image` became `build-6-176277f` |
| Health check | Local actuator `UP`; public HTTPS actuator `UP` |
| Restore staging | Re-run rollback playbook with `build-7-37f911b` |
| Independently inspect | Staging returned to `build-7-37f911b`; health `UP` |
| Production | No production rollback was performed; Build #7 remained in production |

The test establishes that a **specified older image can be redeployed on staging**, and the approved image can be restored. It does not prove an automated revert on failed rollout or a production rollback rehearsal.

## 11. Troubleshooting and lessons learned

| Incident | Diagnosis/approach | Verified resolution or lesson |
|---|---|---|
| Production initially lacked Docker | Read-only SSM command showed Docker absent | `configure.yml` installed/configured it before deployment; production subsequently passed health verification |
| Jenkins stage and SSM command lifecycle | One earlier deployment invocation completed later than Jenkins expected | Poll and inspect SSM statuses/output, rather than assuming a timeout means remote execution failed |
| Maven Checkstyle failure | Generated OWASP `dependency-check-report.xml` interfered with checks | Application `pom.xml` was updated to exclude the generated report; Build #6 subsequently passed |
| Dynamic inventory warning | `tags` variable deprecation emitted by `amazon.aws` | Code uses `ec2_tags.Environment`; warning was nonfatal, with further collection compatibility review deferred |
| Ad hoc Ansible inspection failed | Wrong `hosts.yml` path supplied | Dynamic inventory is generated under `/opt/ansible/inventory/aws_ec2.yml`; validate using correct inventory or SSM directly |
| Rollback initially needed independent confirmation | Playbook success alone does not prove exact running image | `docker inspect ... --format '{{.Config.Image}}'` plus application health was used |
| Shared DNS concerns during destroy | Certificate-validation CNAME might matter beyond Ansible project | Its Route 53 record was preserved by removing that record from Ansible Terraform state management |

## 12. Backup, teardown and recovery

### Last confirmed repository checkpoints

- Infrastructure `main`: `ee9b7dc`, including `.gitignore` exclusions for local recovery files.
- Application `feature/ansible-nexus-pipeline`: `37f911b` (latest explicitly confirmed push in this record).

### S3 archive inventory (verified present before teardown)

Bucket: `ferdinice-devops-secure-backups-740994137090`.

| Service | Archive | Size reported |
|---|---|---|
| Jenkins | `jenkins/jenkins-backup-20261014-002729.tar.gz` | 156.9 MiB |
| Nexus | `nexus/nexus-backup-20261014-003725.tar.gz` | 1.8 MiB |
| SonarQube | `sonarqube/sonarqube-backup-20261014.tar.gz` | 4.9 MiB |

These archived service backups predated Build #7. Their object existence was checked, but a complete restore test of these archives was **not** recorded.

### EBS snapshot inventory (all reached `completed`, 100%)

Snapshot batch: `20261018-224952`, region `eu-west-3`.

| Host | Snapshot ID |
|---|---|
| Jenkins | `snap-04f0ffdb3bd954b44` |
| Nexus | `snap-0c924a2a63fdb29c6` |
| SonarQube | `snap-0e9caa656989ef08f` |
| Ansible controller | `snap-00a1d7566312bbd2f` |
| Prometheus | `snap-0df0069cb3c8cdd59` |
| Grafana | `snap-0de7aaf3ca3ea456b` |
| Staging | `snap-08810db36175328e7` |
| Production | `snap-07adbb9b53208ca34` |

Snapshots were taken from running hosts and are not demonstrated to be application-consistent. They preserve volume blocks, not the entire VPC, DNS, role configuration or automatically bootable full-stack instance definitions.

### Terraform state backup and destroy

- Local recovery files: `backups/2026-10-18/terraform.tfstate` (361 KB), `backups/2026-10-18/snapshots.txt`.
- State JSON validation passed; **keep the state backup encrypted and private**.
- Initial destroy plan targeted 109 deletions; the certificate-validation DNS record was removed from Terraform management without deleting it.
- Revised plan targeted 108 deletions, excluding EBS snapshots and S3 buckets and preserving the validation CNAME.
- Terraform reported: `Apply complete! Resources: 0 added, 0 changed, 108 destroyed.`
- Post-destroy command `terraform state list | wc -l` returned `0`.

`terraform state list == 0` validates the Terraform state, **not** absence of every possibly chargeable AWS object. Snapshots and backup buckets are deliberately retained and incur costs. Reconcile any untracked cloud resources separately.

### Restore runbook — planning guidance, not yet demonstrated

**Do not run `terraform apply` assuming snapshot contents will automatically be mounted on new servers.** The repository's standard EC2 definitions use fresh root volumes. A restore workflow must explicitly integrate the saved snapshot data or an appropriately created AMI/volume into newly created instances, and validate bootstrapping and service consistency.

Recommended recovery sequence:

1. Confirm AWS account, `eu-west-3`, Terraform backend bucket, backups and all eight snapshots still exist.
2. Securely preserve the backed-up Terraform state and identify required IAM/SSM parameters and GitHub branch/commit revisions.
3. Decide between fresh Terraform provisioning plus application-level restore, and machine recovery using EBS snapshots/derived AMIs. Document volume-to-instance mapping and whether root-volume replacement is supported by the chosen instance launch mechanism.
4. Review Terraform plan carefully for DNS conflicts and any effects on resources outside the Ansible VPC.
5. Provision or restore platform components in dependency order (networking, IAM/security, services, application nodes); restore Jenkins/Nexus/SonarQube data and secrets with least privilege.
6. Restore configuration/repositories, regenerate or recover necessary keys and secrets, reconnect ALB/DNS/TLS, then validate SSM, Jenkins plugins/credentials/jobs, Nexus image availability and SonarQube state.
7. Verify Ansible dynamic inventory and both Docker environments; redeploy the approved image from Nexus (or preserved artifacts).
8. Verify external HTTPS, Prometheus targets, Grafana panels and controlled release/rollback behavior.

**Recovery gaps to close before claiming disaster recovery readiness:** verify encrypted off-machine storage for the local Terraform state/manifest; test actual restoration of service archives or snapshots; make database-specific consistent SonarQube backups where required; assess service credentials, SSH private key and DNS/certificate revalidation; and document actual RTO/RPO from a recovery exercise.

## 13. Security assessment

**Demonstrated controls:** IAM instance roles; encrypted SSM Parameter Store retrieval for registry credentials and the Ansible SSH key; minimal read-only `s3:GetObject` prefixes for host restore permissions; gated Jenkins quality/security steps; manual Jenkins production approval; HTTPS through ALB/ACM; private application hosts and dynamic AWS-tag-scoped inventory.

**Improvements/limitations to document honestly:** application credentials and instance profiles require periodic rotation and review; Jenkins and its controller remain privileged infrastructure; SSM permissions should be audited for resource scope; Ansible bootstrap disables SSH host key checking (`host_key_checking = False`), which is a lab convenience rather than a hardened enterprise default; SonarQube/OWASP stages should be paired with defined enforcement thresholds and evidence for vulnerability-policy outcomes; and saved state/snapshots must be controlled for sensitive data.

## 14. Portfolio presentation and interview-ready project description

> Designed and implemented an AWS-based DevSecOps delivery platform using Terraform, Jenkins, Maven, SonarQube, OWASP Dependency-Check, Nexus, Docker and Ansible. Built reusable Ansible roles with AWS EC2 dynamic inventory to configure staging and production servers. Implemented quality gates, immutable container images, staging-first deployment and manually approved production promotion via AWS Systems Manager. Validated application HTTPS health, Prometheus/Grafana monitoring and an image rollback/restoration exercise. Secured backups and performed a controlled infrastructure teardown to manage cloud costs.

### Useful evidence to retain (outside public Git)

- Jenkins Build #7 all-green pipeline screenshot and console log.
- SSM deployment logs and corresponding image/actuator inspection outputs.
- Staging and production external HTTP 200 verification.
- Prometheus UP targets and Grafana dashboard screenshots.
- Rollback from Build #7 to Build #6, then restoration evidence.
- Eight completed EBS snapshot IDs and snapshot verification results.
- Reviewed destroy-plan summary and post-destroy empty Terraform state.

Avoid publishing secrets, account identifiers if not necessary, private keys, unredacted state or environment-specific credentials.

## 15. Future work after documentation

The technical implementation and demonstrated validations are complete. Remaining improvement items include documenting/bootstrap-hardening the AWS inventory dependency, testing genuine disaster recovery, formalizing production rollback procedures, verifying alert notifications, and improving portability of configuration/restore scripts.

The **learning programme follows documentation completion**, starting with Linux/Git/YAML, then AWS networking and Terraform, Jenkins/CI, Docker/Nexus, Ansible fundamentals, monitoring, security and realistic troubleshooting. No immediate infrastructure rebuild is required to study these topics.

---

### Evidence and provenance

This document is grounded in the reviewed GitHub files for `ansible-devops-platform` and `Jenkinsfile.ansible` at the named branch, together with command output and screenshots supplied in the project conversation. Statements about running services refer to **historical pre-destruction validation**. Recovery instructions are proposed operating procedures, not a claim that restoring the whole platform has been successfully tested.
