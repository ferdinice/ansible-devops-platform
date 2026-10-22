# Rollback Runbook — Pet Adoption / Ansible Platform

**Purpose:** Redeploy an existing known-good Nexus image without rebuilding source code.  
**Scope:** Staging or production EC2 application nodes managed by the Ansible controller.  
**Availability:** Requires a rebuilt/running platform. Infrastructure is currently destroyed following successful October 2026 testing.

## 1. How rollback works

`module/ansible/playbooks/rollback.yml` selects `hosts: "{{ target_env | default('stage') }}"`, requires an explicit nonempty `app_image_tag`, and executes the same `app` role used for standard deployment. That role authenticates to Nexus using a deploy-reader secret from AWS SSM, pulls the immutable image, updates the `pet-adoption` container and verifies `http://127.0.0.1:8080/actuator/health` returns 200.

**Do not confuse this with infrastructure disaster recovery.** Rolling back an application container does not recover deleted VPCs, instances, databases or service storage.

## 2. Safety checks

1. Confirm the AWS account, region (`eu-west-3`), target environment, change approval, and active incident.
2. Identify the current container's exact image tag. Verify the desired older tag exists in Nexus or in the intended host's local cache; prefer verification against Nexus because a local cache is not a durable artifact repository.
3. Confirm the previous image is compatible with current configuration and data schema. The example application used its default H2 setup; app-level rollback is **not** a database rollback.
4. Ensure Ansible's AWS EC2 dynamic inventory discovers exactly the intended staging or production host(s). Avoid running without `target_env` on production incidents; its default is `stage`.
5. Record the image tag currently running so that it can be reinstated if needed.

## 3. Execute staging rollback

On a working Ansible controller, with its generated `/etc/ansible/ansible.cfg` and credentials in place:

```bash
sudo -iu ubuntu ansible-playbook \
  /opt/ansible/repo/module/ansible/playbooks/rollback.yml \
  -e target_env=stage \
  -e app_image_tag=build-6-176277f
```

The tags here refer to **historically tested** images; on a later deployment select an actually available and compatible image. To execute remotely from an authorised workstation, use `aws ssm send-command` with `AWS-RunShellScript` targeting only the dedicated Ansible controller. Inspect the SSM invocation result and Ansible `PLAY RECAP`; `Status=Success` by itself is insufficient if post-command verification was omitted.

## 4. Independently verify

On the target application EC2 through SSM:

```bash
sudo docker inspect pet-adoption --format '{{.Config.Image}}'
curl -fsS http://127.0.0.1:8080/actuator/health
```

From an authorised client:

```bash
curl -fsS https://stage.ferdeve.fit/actuator/health
```

The first command must display the requested immutable tag. Both health endpoints should return an `UP` response. Inspect service logs, ALB health and monitored metrics if needed.

## 5. Restore the current approved release

After a successful staging rollback test, restore the version that was previously approved:

```bash
sudo -iu ubuntu ansible-playbook \
  /opt/ansible/repo/module/ansible/playbooks/rollback.yml \
  -e target_env=stage \
  -e app_image_tag=build-7-37f911b
```

Repeat independent image and HTTPS health checks. **Production rollback** follows the same method with `-e target_env=prod` but must require explicit change approval, incident assessment and a verified rollback candidate; do not automatically reuse the staging test tag on production.

## 6. Historical test record

- Initial approved staging/production image: `registry.ferdeve.fit/pet-adoption-docker:build-7-37f911b`.
- Staging rollback ran the Ansible playbook with `build-6-176277f`, recap `ok=10`, `changed=2`, `failed=0`.
- An independent EC2 Docker inspection confirmed Build #6; staging HTTPS returned `{"status":"UP"}`.
- Staging restoration to Build #7 ran successfully, recap `ok=10`, `changed=2`, `failed=0`.
- Independent inspection showed Build #7 and local/HTTPS health checks returned `UP`.
- Production was **not** modified during this rollback test. A production rollback was **not** tested.

## 7. Known limitations

- `recreate: false` in the app role does not force recreation solely for the sake of recreation; the historical version change did cause a container update. Always verify the running image.
- Prior ad hoc validation attempted `module/ansible/inventories/stage/hosts.yml`, but that file does not exist; rely on the controller's generated AWS EC2 inventory or inspect the instance with SSM.
- Warm-up health checks can retry before succeeding. Investigate persistent failures rather than judging a few retries as final failure.
- A failed rollback requires incident response. Do not loop between tags blindly; preserve logs and restore service deliberately.

Related: [`deployment-runbook.md`](deployment-runbook.md), [`disaster-recovery.md`](disaster-recovery.md).
