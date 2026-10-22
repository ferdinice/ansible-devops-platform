# Disaster Recovery Runbook — Ansible Enterprise DevOps Platform

**Recovery status:** Backups were created and listed; a full restoration has **not** been executed or verified.  
**Region:** `eu-west-3`  
**Important:** The Ansible platform was intentionally destroyed after testing: Terraform reported `108 destroyed`, and `terraform state list | wc -l` returned `0`. **Do not push a historical state snapshot into the current empty remote backend.** The original Kubernetes enterprise project is outside this recovery scope.

## 1. Recovery materials recorded

| Server | EBS snapshot (October 18, 2026 batch) |
|---|---|
| Jenkins | `snap-04f0ffdb3bd954b44` |
| Nexus | `snap-0c924a2a63fdb29c6` |
| SonarQube | `snap-0e9caa656989ef08f` |
| Ansible controller | `snap-00a1d7566312bbd2f` |
| Prometheus | `snap-0df0069cb3c8cdd59` |
| Grafana | `snap-0de7aaf3ca3ea456b` |
| Staging | `snap-08810db36175328e7` |
| Production | `snap-07adbb9b53208ca34` |

All eight reported `completed`, `100%` before infrastructure teardown. These were taken from running EC2 volumes and should be considered **crash-consistent**, not proof of application-consistent backups.

Additional S3 archives, listed before teardown in `s3://ferdinice-devops-secure-backups-740994137090/`:

- `jenkins/jenkins-backup-20261014-002729.tar.gz` (156.9 MiB)
- `nexus/nexus-backup-20261014-003725.tar.gz` (1.8 MiB)
- `sonarqube/sonarqube-backup-20261014.tar.gz` (4.9 MiB)

These archives predate the final production release. Presence/size was confirmed; **archive contents and restorability were not validated**. A small Nexus archive may not contain the Docker blob store. Do not assume that Nexus images survive the rebuild.

Repository references:
- Infra: `https://github.com/ferdinice/ansible-devops-platform` (verified commits `b5ac6bb`, then cleanup checkpoint `ee9b7dc`; use current reviewed HEAD after documentation commit).
- Application: `https://github.com/ferdinice/pet-adoption-devops`, `feature/ansible-nexus-pipeline`, commit `37f911b`.
- Local recovery files: `backups/2026-10-18/terraform.tfstate` (361 KB), `backups/2026-10-18/snapshots.txt`. `.gitignore` intentionally excludes backups. Store an additional **encrypted and access-controlled** copy off the workstation. Terraform state can contain sensitive material.
- Remote Terraform backend: `s3://ansible-devops-platform-tfstate-740994137090/platform/terraform.tfstate`; configured with S3 lockfile.

## 2. First action: Verify, don't modify

Confirm identity, role permissions, account and region. Check current backup existence (snapshots and S3) with read-only AWS commands:

```bash
aws sts get-caller-identity --profile personal-devops
aws ec2 describe-snapshots --region eu-west-3 --owner-ids self \
  --filters 'Name=tag:BackupDate,Values=20261018-224952' \
  --query 'Snapshots[].[SnapshotId,State,VolumeId,Description]' --output table
aws s3 ls s3://ferdinice-devops-secure-backups-740994137090/ --recursive
aws s3 ls s3://ansible-devops-platform-tfstate-740994137090/platform/
```

Check key retention, KMS permissions, credential store integrity, certificate/Route 53 zone ownership and budget before provisioning. Snapshot restore is impossible if underlying KMS keys are unavailable.

## 3. Select recovery method explicitly

**Path A — Recreate infrastructure cleanly:** Use Terraform to provision a fresh environment, then reinstall/configure Jenkins, Nexus, SonarQube, Ansible and monitoring. Suitable for reproducibility testing, **not a shortcut to preserve old Jenkins/Nexus data**.

**Path B — Recover previous service state:** Create recovery volumes from appropriate snapshots in matching Availability Zones or AMIs from snapshots, ensure OS/instance compatibility, and integrate them into Terraform-managed instances using a documented mechanism (for example reviewed `root_block_device`/launch template changes, suitable AMIs, or carefully managed volume attachment). The current Terraform configuration does **not** automatically consume the eight snapshot IDs. Do not attach a root-volume snapshot as an arbitrary data volume and expect its services to start automatically.

For data consistency, consider restoring service-aware S3 archives where validated and compare with snapshot content. Do **not** overwrite a live service with older archive content without a known recovery point and rollback plan.

## 4. Recreate shared infrastructure

Reconcile Terraform configuration with any resources intentionally preserved outside state. During teardown, the ACM validation DNS CNAME `_8806ad37d366d5b0d666f5bd1e060d78.ferdeve.fit` was removed from Terraform state **without deleting the Route 53 record**. A fresh apply may try to create this same record; evaluate an import, a managed-data/read-only strategy, or a controlled config change instead of blind overwrite.

The Terraform-backed key pair and SSM private-key parameter were in the destroy plan. Recreating a new key pair changes SSH trust/credentials and must be coordinated with the Ansible controller and managed nodes. Nexus/SonarQube/Jenkins SecureStrings and IAM restores also require verification; SSM-managed secrets should never be placed in Git or plaintext documentation.

Review `terraform plan` before `terraform apply`; this must only target the Ansible VPC and its scoped service DNS. Preserve original Kubernetes resources and any other `ferdeve.fit` endpoints.

## 5. Restore application/platform services

1. Jenkins: Recover its intended home data (jobs, credentials encryption material, plugin configurations), recheck exact plugin compatibility and avoid exposing secrets. A Jenkins archive without matching secrets or plugins may not restore fully.
2. Nexus: Confirm Docker registry endpoint, repository format and blob store. Verify required immutable images exist; if not, rebuild from the preserved application commit and produce a **new** traceable release, rather than claiming the historical image is present.
3. SonarQube: Confirm database/state compatibility, application version and tokens/webhooks; restore with a service-consistent database snapshot where available.
4. Ansible controller: Its user-data generates the EC2 dynamic inventory at `/opt/ansible/inventory/aws_ec2.yml`. Verify role, SSH key, `amazon.aws` collection, group membership and ability to reach private nodes.
5. Prometheus/Grafana: Recover datasource, dashboards and scrape jobs; verify Node Exporter on stage/prod. Historical metrics retention requires separate attention if needed.
6. Stage/prod: Confirm Docker image/health. Never assume the snapshots contain the most recent Nexus artifact if image blobs were stored elsewhere.

## 6. Acceptance criteria

- Terraform plan and state align with actual live Ansible infrastructure, with no shared/Kubernetes resources unintentionally claimed.
- Jenkins builds/tests and passes SonarQube Quality Gate, publishes a verified Nexus manifest, and triggers Ansible with SSM.
- Staging and production deploy the *same immutable image* following manual approval.
- Docker inspection confirms version, HTTP `/actuator/health` returns `UP`, ALB and HTTPS return HTTP 200.
- Prometheus stage/prod target status `UP`; Grafana dashboards display CPU, memory and other metrics.
- A controlled staging rollback and restoration succeed; production remains change-controlled.
- Secrets, user accounts, credentials, backup integrity and configuration drift have been assessed.

## 7. Risks and operating guardrails

- EBS snapshots and archived tarballs were **not** subjected to a full recovery rehearsal. Restoration complexity and missing data are real risks.
- Backups retained in AWS incur storage charges even when compute resources are destroyed.
- A historical Terraform state file must never be applied or pushed over the new empty backend solely to recreate infrastructure; that can cause state conflicts and dangerous unintended deletes.
- The original Kubernetes/KOps project has a distinct infrastructure lifecycle. The Ansible teardown did not list Kubernetes resources, but its live status was not independently verified.
- Retain the GitHub commits, encrypted state backup and snapshot manifest as provenance; record subsequent restore changes explicitly.

Related: [`deployment-runbook.md`](deployment-runbook.md), [`rollback-runbook.md`](rollback-runbook.md).
