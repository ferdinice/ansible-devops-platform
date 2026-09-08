#!/bin/bash

set -euo pipefail

exec > >(tee /var/log/nexus-userdata.log | logger -t user-data -s 2>/dev/console) 2>&1

echo "========================================"
echo "Starting Nexus installation..."
echo "========================================"

export DEBIAN_FRONTEND=noninteractive

apt-get update -y

apt-get install -y \
  openjdk-21-jre \
  wget \
  curl \
  tar

NEXUS_VERSION="3.80.0-06"
NEXUS_USER="nexus"
NEXUS_INSTALL_DIR="/opt/nexus"
NEXUS_DATA_DIR="/opt/sonatype-work"

useradd --system --no-create-home --shell /usr/sbin/nologin ${NEXUS_USER} || true

cd /tmp

wget -O nexus.tar.gz \
  "https://download.sonatype.com/nexus/3/nexus-${NEXUS_VERSION}-linux-x86_64.tar.gz"

tar -xzf nexus.tar.gz

mv "nexus-${NEXUS_VERSION}" "${NEXUS_INSTALL_DIR}"
mv sonatype-work "${NEXUS_DATA_DIR}"

chown -R ${NEXUS_USER}:${NEXUS_USER} "${NEXUS_INSTALL_DIR}"
chown -R ${NEXUS_USER}:${NEXUS_USER} "${NEXUS_DATA_DIR}"

echo "run_as_user=${NEXUS_USER}" > "${NEXUS_INSTALL_DIR}/bin/nexus.rc"

cat > /etc/systemd/system/nexus.service <<EOF
[Unit]
Description=Nexus Repository Manager
After=network.target

[Service]
Type=forking
LimitNOFILE=65536
ExecStart=${NEXUS_INSTALL_DIR}/bin/nexus start
ExecStop=${NEXUS_INSTALL_DIR}/bin/nexus stop
User=${NEXUS_USER}
Restart=on-abort
Environment=HOME=${NEXUS_INSTALL_DIR}
WorkingDirectory=${NEXUS_INSTALL_DIR}

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable nexus
systemctl start nexus

echo "========================================"
echo "Nexus installation completed."
echo "========================================"

systemctl status nexus --no-pager