#!/bin/bash

set -euo pipefail

exec > >(tee /var/log/sonarqube-userdata.log | logger -t user-data -s 2>/dev/console) 2>&1

echo "========================================"
echo "Starting SonarQube installation..."
echo "========================================"

export DEBIAN_FRONTEND=noninteractive

SONAR_VERSION="25.5.0.107428"
SONAR_USER="sonaruser"
SONAR_DIR="/opt/sonarqube"

DB_USER="sonar"
DB_NAME="sonarqube"

# Generate database password locally on the EC2 instance.
# This avoids hard-coding the password in Terraform.
DB_PASSWORD=$(openssl rand -hex 16)

SONAR_ZIP="sonarqube-${SONAR_VERSION}.zip"
SONAR_URL="https://binaries.sonarsource.com/Distribution/sonarqube/${SONAR_ZIP}"


# ============================================================
# INSTALL DEPENDENCIES
# ============================================================

apt-get update -y

apt-get install -y \
  openjdk-17-jdk \
  unzip \
  wget \
  curl \
  openssl \
  postgresql \
  postgresql-contrib


# ============================================================
# START POSTGRESQL
# ============================================================

systemctl enable postgresql
systemctl start postgresql


# ============================================================
# CREATE DATABASE
# ============================================================

runuser -u postgres -- psql <<EOF
CREATE USER ${DB_USER} WITH ENCRYPTED PASSWORD '${DB_PASSWORD}';
CREATE DATABASE ${DB_NAME} OWNER ${DB_USER};
GRANT ALL PRIVILEGES ON DATABASE ${DB_NAME} TO ${DB_USER};
EOF


# ============================================================
# CREATE SONARQUBE USER
# ============================================================

useradd \
  --system \
  --no-create-home \
  --shell /usr/sbin/nologin \
  ${SONAR_USER} || true


# ============================================================
# DOWNLOAD SONARQUBE
# ============================================================

cd /opt

wget -O "${SONAR_ZIP}" "${SONAR_URL}"

unzip "${SONAR_ZIP}"

mv "sonarqube-${SONAR_VERSION}" "${SONAR_DIR}"

chown -R ${SONAR_USER}:${SONAR_USER} "${SONAR_DIR}"


# ============================================================
# CONFIGURE SONARQUBE DATABASE
# ============================================================

SONAR_PROPERTIES="${SONAR_DIR}/conf/sonar.properties"

cat >> "${SONAR_PROPERTIES}" <<EOF

sonar.jdbc.username=${DB_USER}
sonar.jdbc.password=${DB_PASSWORD}
sonar.jdbc.url=jdbc:postgresql://localhost:5432/${DB_NAME}

sonar.web.host=0.0.0.0
sonar.web.port=9000
EOF


# ============================================================
# SYSTEM REQUIREMENTS
# ============================================================

cat >> /etc/security/limits.conf <<EOF
${SONAR_USER} soft nofile 65536
${SONAR_USER} hard nofile 65536
${SONAR_USER} soft nproc 4096
${SONAR_USER} hard nproc 4096
EOF

cat > /etc/sysctl.d/99-sonarqube.conf <<EOF
vm.max_map_count=262144
fs.file-max=65536
EOF

sysctl --system


# ============================================================
# SYSTEMD SERVICE
# ============================================================

cat > /etc/systemd/system/sonarqube.service <<EOF
[Unit]
Description=SonarQube Service
After=network.target postgresql.service
Requires=postgresql.service

[Service]
Type=forking
ExecStart=${SONAR_DIR}/bin/linux-x86-64/sonar.sh start
ExecStop=${SONAR_DIR}/bin/linux-x86-64/sonar.sh stop
User=${SONAR_USER}
Group=${SONAR_USER}
LimitNOFILE=65536
LimitNPROC=4096
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF


# ============================================================
# START SONARQUBE
# ============================================================

systemctl daemon-reload
systemctl enable sonarqube
systemctl start sonarqube

echo "========================================"
echo "SonarQube installation completed."
echo "========================================"

systemctl status sonarqube --no-pager