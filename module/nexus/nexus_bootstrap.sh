#!/usr/bin/env bash

set -euo pipefail

NEXUS_URL="http://localhost:8081"
ADMIN_PASSWORD_FILE="/opt/sonatype-work/nexus3/admin.password"
DOCKER_REPOSITORY="pet-adoption-docker"
DOCKER_PORT="8082"

CI_ROLE="pet-adoption-ci-writer"
DEPLOY_ROLE="pet-adoption-deploy-reader"

CI_USER="nexus-ci-writer"
DEPLOY_USER="nexus-deploy-reader"

CI_PASSWORD_PARAMETER="/devops-platform/nexus/ci-writer-password"
DEPLOY_PASSWORD_PARAMETER="/devops-platform/nexus/deploy-reader-password"

echo "========================================"
echo "Starting Nexus application bootstrap..."
echo "========================================"

# ------------------------------------------------------------
# WAIT FOR NEXUS
# ------------------------------------------------------------

echo "Waiting for Nexus REST API..."

for attempt in {1..60}; do
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
    "${NEXUS_URL}/service/rest/v1/status" || true)

  if [[ "${HTTP_CODE}" == "200" ]]; then
    echo "Nexus REST API is ready."
    break
  fi

  if [[ "${attempt}" -eq 60 ]]; then
    echo "ERROR: Nexus REST API did not become ready."
    exit 1
  fi

  sleep 10
done

if [[ ! -s "${ADMIN_PASSWORD_FILE}" ]]; then
  echo "ERROR: Nexus admin password file does not exist."
  exit 1
fi

ADMIN_PASSWORD=$(cat "${ADMIN_PASSWORD_FILE}")

nexus_api() {
  curl --fail-with-body --silent --show-error \
    -u "admin:${ADMIN_PASSWORD}" "$@"
}

echo "Nexus authentication initialized."

# ============================================================
# ACCEPT NEXUS COMMUNITY EULA
# ============================================================

echo "Checking Nexus EULA status..."

EULA_ACCEPTED=$(
  nexus_api \
    "${NEXUS_URL}/service/rest/v1/system/eula" |
    grep -o '"accepted"[[:space:]]*:[[:space:]]*[^,}]*' |
    grep -o 'true\|false'
)

if [[ "${EULA_ACCEPTED}" != "true" ]]; then
  echo "Accepting Nexus Community Edition EULA..."

  HTTP_CODE=$(
    curl --silent --show-error \
      -o /tmp/nexus-eula-response \
      -w "%{http_code}" \
      -u "admin:${ADMIN_PASSWORD}" \
      -X POST \
      -H "Content-Type: application/json" \
      -d '{"accepted":true}' \
      "${NEXUS_URL}/service/rest/v1/system/eula"
  )

  if [[ "${HTTP_CODE}" != "204" ]]; then
    echo "ERROR: EULA acceptance failed. HTTP ${HTTP_CODE}"
    cat /tmp/nexus-eula-response
    exit 1
  fi

  echo "Nexus EULA accepted."
else
  echo "Nexus EULA already accepted."
fi


# ============================================================
# ENSURE DOCKER HOSTED REPOSITORY
# ============================================================

echo "Checking Docker repository ${DOCKER_REPOSITORY}..."

REPOSITORY_HTTP=$(
  curl --silent \
    -o /tmp/nexus-repository-check \
    -w "%{http_code}" \
    -u "admin:${ADMIN_PASSWORD}" \
    "${NEXUS_URL}/service/rest/v1/repositories/docker/hosted/${DOCKER_REPOSITORY}"
)

case "${REPOSITORY_HTTP}" in
  200)
    echo "Docker repository ${DOCKER_REPOSITORY} already exists."
    ;;

  404)
    echo "Creating Docker repository ${DOCKER_REPOSITORY}..."

    cat >/tmp/nexus-docker-repository.json <<EOF
{
  "name": "${DOCKER_REPOSITORY}",
  "online": true,
  "storage": {
    "blobStoreName": "default",
    "strictContentTypeValidation": true,
    "writePolicy": "allow_once",
    "latestPolicy": true
  },
  "docker": {
    "v1Enabled": false,
    "forceBasicAuth": true,
    "httpPort": ${DOCKER_PORT}
  }
}
EOF

    CREATE_HTTP=$(
      curl --silent --show-error \
        -o /tmp/nexus-repository-create-response \
        -w "%{http_code}" \
        -u "admin:${ADMIN_PASSWORD}" \
        -X POST \
        -H "Content-Type: application/json" \
        --data-binary @/tmp/nexus-docker-repository.json \
        "${NEXUS_URL}/service/rest/v1/repositories/docker/hosted"
    )

    if [[ "${CREATE_HTTP}" != "201" ]]; then
      echo "ERROR: Docker repository creation failed. HTTP ${CREATE_HTTP}"
      cat /tmp/nexus-repository-create-response
      exit 1
    fi

    echo "Docker repository ${DOCKER_REPOSITORY} created."
    ;;

  *)
    echo "ERROR: Repository check returned HTTP ${REPOSITORY_HTTP}"
    cat /tmp/nexus-repository-check
    exit 1
    ;;
esac

# ============================================================
# ENSURE NEXUS SECURITY ROLES
# ============================================================

ensure_role() {
  local role_id="$1"
  local role_name="$2"
  local role_description="$3"
  local privileges_json="$4"

  echo "Checking Nexus role ${role_id}..."

  local check_http
  check_http=$(
    curl --silent \
      -o "/tmp/${role_id}-check.json" \
      -w "%{http_code}" \
      -u "admin:${ADMIN_PASSWORD}" \
      "${NEXUS_URL}/service/rest/v1/security/roles/${role_id}"
  )

  cat >"/tmp/${role_id}.json" <<EOF
{
  "id": "${role_id}",
  "name": "${role_name}",
  "description": "${role_description}",
  "privileges": ${privileges_json},
  "roles": []
}
EOF

  case "${check_http}" in
    200)
      echo "Role ${role_id} exists. Ensuring configuration is current..."

      local update_http
      update_http=$(
        curl --silent --show-error \
          -o "/tmp/${role_id}-update-response" \
          -w "%{http_code}" \
          -u "admin:${ADMIN_PASSWORD}" \
          -X PUT \
          -H "Content-Type: application/json" \
          --data-binary @"/tmp/${role_id}.json" \
          "${NEXUS_URL}/service/rest/v1/security/roles/${role_id}"
      )

      if [[ "${update_http}" != "200" && "${update_http}" != "204" ]]; then
        echo "ERROR: Role ${role_id} update failed. HTTP ${update_http}"
        cat "/tmp/${role_id}-update-response"
        exit 1
      fi

      echo "Role ${role_id} is current."
      ;;

    404)
      echo "Creating Nexus role ${role_id}..."

      local create_http
      create_http=$(
        curl --silent --show-error \
          -o "/tmp/${role_id}-create-response" \
          -w "%{http_code}" \
          -u "admin:${ADMIN_PASSWORD}" \
          -X POST \
          -H "Content-Type: application/json" \
          --data-binary @"/tmp/${role_id}.json" \
          "${NEXUS_URL}/service/rest/v1/security/roles"
      )

      if [[ "${create_http}" != "200" ]]; then
        echo "ERROR: Role ${role_id} creation failed. HTTP ${create_http}"
        cat "/tmp/${role_id}-create-response"
        exit 1
      fi

      echo "Role ${role_id} created."
      ;;

    *)
      echo "ERROR: Role ${role_id} check returned HTTP ${check_http}"
      cat "/tmp/${role_id}-check.json"
      exit 1
      ;;
  esac
}


# Jenkins: push/build-image permissions.
ensure_role \
  "${CI_ROLE}" \
  "Pet Adoption CI Writer" \
  "Least-privilege role for Jenkins to push Docker images to ${DOCKER_REPOSITORY}" \
  '[
    "nx-repository-view-docker-pet-adoption-docker-add",
    "nx-repository-view-docker-pet-adoption-docker-browse",
    "nx-repository-view-docker-pet-adoption-docker-edit",
    "nx-repository-view-docker-pet-adoption-docker-read"
  ]'


# Ansible/deployment nodes: pull-only permissions.
ensure_role \
  "${DEPLOY_ROLE}" \
  "Pet Adoption Deploy Reader" \
  "Read-only role for Ansible deployments to pull Docker images from pet-adoption-docker" \
  '[
    "nx-repository-view-docker-pet-adoption-docker-browse",
    "nx-repository-view-docker-pet-adoption-docker-read"
  ]'

  # ============================================================
# ENSURE NEXUS USERS AND SSM CREDENTIALS
# ============================================================

ensure_user() {
  local user_id="$1"
  local first_name="$2"
  local last_name="$3"
  local email="$4"
  local role_id="$5"
  local parameter_name="$6"

  echo "Ensuring Nexus user ${user_id}..."

  # Reuse the existing credential when it already exists in SSM.
  # Otherwise generate a strong password for the first bootstrap.
  if USER_PASSWORD=$(
    aws ssm get-parameter \
      --name "${parameter_name}" \
      --with-decryption \
      --region eu-west-3 \
      --query 'Parameter.Value' \
      --output text 2>/dev/null
  ); then
    echo "Existing credential found in SSM for ${user_id}."
  else
    echo "Generating credential for ${user_id}..."

    USER_PASSWORD=$(
      openssl rand -base64 48 |
        tr -d '\n' |
        tr '/+' '_-'
    )

    aws ssm put-parameter \
      --name "${parameter_name}" \
      --description "Nexus credential for ${user_id}" \
      --type SecureString \
      --value "${USER_PASSWORD}" \
      --overwrite \
      --region eu-west-3 >/dev/null

    echo "Credential stored in SSM for ${user_id}."
  fi

  local check_http
  check_http=$(
    curl --silent --show-error \
      -o "/tmp/${user_id}-check.json" \
      -w "%{http_code}" \
      -u "admin:${ADMIN_PASSWORD}" \
      --get \
      --data-urlencode "userId=${user_id}" \
      --data-urlencode "source=default" \
      "${NEXUS_URL}/service/rest/v1/security/users"
  )

  if [[ "${check_http}" != "200" ]]; then
    echo "ERROR: User ${user_id} lookup failed. HTTP ${check_http}"
    cat "/tmp/${user_id}-check.json"
    exit 1
  fi

  # The collection endpoint returns HTTP 200 even when no user matches.
  # An exact userId match means the Nexus user already exists.
  if grep -q "\"userId\"[[:space:]]*:[[:space:]]*\"${user_id}\"" \
    "/tmp/${user_id}-check.json"; then

    echo "Nexus user ${user_id} already exists."

    # Keep the Nexus password synchronized with the credential
    # persisted in SSM Parameter Store.
    local password_http
    password_http=$(
      curl --silent --show-error \
        -o "/tmp/${user_id}-password-response" \
        -w "%{http_code}" \
        -u "admin:${ADMIN_PASSWORD}" \
        -X PUT \
        -H "Content-Type: text/plain" \
        --data-binary "${USER_PASSWORD}" \
        "${NEXUS_URL}/service/rest/v1/security/users/${user_id}/change-password"
    )

    if [[ "${password_http}" != "204" ]]; then
      echo "ERROR: Password synchronization failed for ${user_id}. HTTP ${password_http}"
      cat "/tmp/${user_id}-password-response"
      exit 1
    fi

    echo "Credential synchronized for ${user_id}."
    return
  fi

  echo "Creating Nexus user ${user_id}..."

  cat >"/tmp/${user_id}.json" <<EOF
{
  "userId": "${user_id}",
  "firstName": "${first_name}",
  "lastName": "${last_name}",
  "emailAddress": "${email}",
  "password": "${USER_PASSWORD}",
  "status": "active",
  "roles": [
    "${role_id}"
  ]
}
EOF

  local create_http
  create_http=$(
    curl --silent --show-error \
      -o "/tmp/${user_id}-create-response" \
      -w "%{http_code}" \
      -u "admin:${ADMIN_PASSWORD}" \
      -X POST \
      -H "Content-Type: application/json" \
      --data-binary @"/tmp/${user_id}.json" \
      "${NEXUS_URL}/service/rest/v1/security/users"
  )

  if [[ "${create_http}" != "200" ]]; then
    echo "ERROR: User ${user_id} creation failed. HTTP ${create_http}"
    cat "/tmp/${user_id}-create-response"
    exit 1
  fi

  echo "Nexus user ${user_id} created."
}


ensure_user \
  "${CI_USER}" \
  "Nexus" \
  "CI Writer" \
  "nexus-ci-writer@ferdeve.fit" \
  "${CI_ROLE}" \
  "${CI_PASSWORD_PARAMETER}"


ensure_user \
  "${DEPLOY_USER}" \
  "Nexus" \
  "Deploy Reader" \
  "nexus-deploy-reader@ferdeve.fit" \
  "${DEPLOY_ROLE}" \
  "${DEPLOY_PASSWORD_PARAMETER}"


# ============================================================
# CLEAN UP TEMPORARY SECRET-BEARING FILES
# ============================================================

rm -f \
  "/tmp/${CI_USER}.json" \
  "/tmp/${DEPLOY_USER}.json"

unset USER_PASSWORD
unset ADMIN_PASSWORD

echo "========================================"
echo "Nexus application bootstrap completed."
echo "========================================"