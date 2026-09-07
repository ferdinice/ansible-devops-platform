#!/bin/bash

set -euo pipefail

exec > >(tee /var/log/jenkins-userdata.log | logger -t user-data -s 2>/dev/console) 2>&1

echo "========================================"
echo "Starting Jenkins installation..."
echo "========================================"

export DEBIAN_FRONTEND=noninteractive

apt-get update -y

apt-get install -y \
  fontconfig \
  openjdk-21-jre \
  curl \
  ca-certificates

# Create apt keyring directory
mkdir -p /etc/apt/keyrings

# Install current Jenkins LTS repository signing key
curl -fsSL \
  https://pkg.jenkins.io/debian-stable/jenkins.io-2026.key \
  -o /etc/apt/keyrings/jenkins-keyring.asc

# Add Jenkins LTS repository
echo "deb [signed-by=/etc/apt/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" \
  > /etc/apt/sources.list.d/jenkins.list

apt-get update -y

apt-get install -y jenkins

systemctl daemon-reload
systemctl enable jenkins
systemctl start jenkins

echo "========================================"
echo "Jenkins installation completed."
echo "========================================"

java -version
systemctl status jenkins --no-pager