#!/usr/bin/env bash
set -euo pipefail

SONAR_PROPERTIES="/opt/sonarqube/conf/sonar.properties"
DB_USER="sonar"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "ERROR: Run this script as root."
  exit 1
fi

if [[ ! -f "$SONAR_PROPERTIES" ]]; then
  echo "ERROR: SonarQube configuration not found."
  exit 1
fi

# Read the restored SonarQube database password.
# Do not print the password.
DB_PASSWORD="$(
  sed -n 's/^sonar\.jdbc\.password=//p' "$SONAR_PROPERTIES" |
  tail -n 1 |
  tr -d '\r'
)"

if [[ -z "$DB_PASSWORD" ]]; then
  echo "ERROR: Database password missing from sonar.properties."
  exit 1
fi

# PostgreSQL's psql variable quoting safely handles password characters.
# The password is supplied through stdin rather than command arguments.
export SONAR_RESTORE_DB_PASSWORD="$DB_PASSWORD"

runuser -u postgres -- \
  psql -X -v ON_ERROR_STOP=1 \
  -d postgres \
  -v db_password="$SONAR_RESTORE_DB_PASSWORD" \
  <<'SQL'
\set QUIET on
ALTER ROLE sonar WITH PASSWORD :'db_password';
SQL

# Verify the restored credentials against PostgreSQL.
# Use TCP so PostgreSQL checks password authentication.
if ! PGPASSWORD="$DB_PASSWORD" psql   -h 127.0.0.1   -U sonar   -d sonarqube   -X -q -t -A   -c "SELECT 1" | grep -qx '1'; then
  echo "ERROR: PostgreSQL authentication verification failed."
  exit 1
fi

unset DB_PASSWORD SONAR_RESTORE_DB_PASSWORD

chmod 600 "$SONAR_PROPERTIES"
chown sonaruser:sonaruser "$SONAR_PROPERTIES"

systemctl restart sonarqube

echo "Waiting for SonarQube to become healthy..."

for attempt in $(seq 1 60); do
  if curl -fsS --max-time 5 \
    http://127.0.0.1:9000/api/system/status |
    grep -q '"status":"UP"'; then
    echo "SUCCESS: SonarQube is UP."
    exit 0
  fi

  sleep 10
done

echo "ERROR: SonarQube did not become healthy."
exit 1
