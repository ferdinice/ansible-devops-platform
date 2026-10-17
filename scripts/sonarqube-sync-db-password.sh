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

# Build a restricted SQL file without exposing credentials
# through process arguments or command output.
SQL_FILE="$(mktemp)"
chmod 600 "$SQL_FILE"
trap 'rm -f "$SQL_FILE"' EXIT

export DB_PASSWORD SQL_FILE

python3 - <<'PYSQL'
import os

password = os.environ["DB_PASSWORD"]
sql_file = os.environ["SQL_FILE"]

# Quote the PostgreSQL string literal safely.
quoted = "'" + password.replace("'", "''") + "'"

with open(sql_file, "w") as f:
    f.write("ALTER ROLE sonar WITH PASSWORD " + quoted + ";\n")
PYSQL

# Keep the SQL file private to root (mode 600).
runuser -u postgres -- psql -X -q -v ON_ERROR_STOP=1   -d postgres < "$SQL_FILE" >/dev/null

rm -f "$SQL_FILE"
trap - EXIT

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
