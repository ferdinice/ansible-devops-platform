#!/bin/bash

set -euo pipefail

exec > >(tee /var/log/jenkins-userdata.log | logger -t user-data -s 2>/dev/console) 2>&1

echo "========================================"
echo "Starting Jenkins installation..."
echo "========================================"

export DEBIAN_FRONTEND=noninteractive
export AWS_DEFAULT_REGION="eu-west-3"

# ============================================================
# SYSTEM PACKAGES
# ============================================================

apt-get update -y

apt-get install -y \
  fontconfig \
  openjdk-21-jre \
  curl \
  ca-certificates \
  unzip \
  git \
  maven

mkdir -p /etc/apt/keyrings


# ============================================================
# AWS CLI V2
# ============================================================

cd /tmp

curl -fsSL \
  "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" \
  -o awscliv2.zip

unzip -q awscliv2.zip
./aws/install

rm -rf aws awscliv2.zip


# ============================================================
# DOCKER CE
# ============================================================

curl -fsSL \
  https://download.docker.com/linux/ubuntu/gpg \
  -o /etc/apt/keyrings/docker.asc

chmod 0644 /etc/apt/keyrings/docker.asc

cat >/etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: noble
Components: stable
Architectures: amd64
Signed-By: /etc/apt/keyrings/docker.asc
EOF

apt-get update -y

apt-get install -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin

systemctl enable docker
systemctl start docker


# ============================================================
# JENKINS
# ============================================================

curl -fsSL \
  https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key \
  -o /etc/apt/keyrings/jenkins-keyring.asc

echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
  > /etc/apt/sources.list.d/jenkins.list

apt-get update -y

apt-get install -y jenkins


# ============================================================
# JENKINS DOCKER ACCESS
# ============================================================

usermod -aG docker jenkins


# ============================================================
# START JENKINS
# ============================================================

systemctl daemon-reload
systemctl enable jenkins
systemctl restart jenkins


# ============================================================
# VERIFICATION
# ============================================================

echo "========================================"
echo "Jenkins installation completed."
echo "========================================"

java -version
mvn --version
docker --version
docker compose version
aws --version
git --version

systemctl is-active docker
systemctl is-active jenkins

id jenkins

systemctl status jenkins --no-pager
