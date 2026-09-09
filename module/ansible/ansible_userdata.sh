#!/bin/bash

set -euo pipefail

exec > >(tee /var/log/ansible-userdata.log | logger -t user-data -s 2>/dev/console) 2>&1

echo "========================================"
echo "Starting Ansible controller setup..."
echo "========================================"

export DEBIAN_FRONTEND=noninteractive

# ============================================================
# SYSTEM PACKAGES
# ============================================================

apt-get update -y

apt-get install -y \
  python3 \
  python3-pip \
  python3-venv \
  git \
  curl \
  unzip \
  jq \
  software-properties-common


# ============================================================
# INSTALL ANSIBLE
# ============================================================

apt-add-repository --yes --update ppa:ansible/ansible

apt-get install -y ansible


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
# PYTHON AWS DEPENDENCIES
# Needed for aws_ec2 dynamic inventory
# ============================================================

apt-get install -y python3-boto3 python3-botocore


# ============================================================
# ANSIBLE AWS COLLECTION
# ============================================================

ansible-galaxy collection install amazon.aws


# ============================================================
# ANSIBLE WORKING DIRECTORY
# ============================================================

mkdir -p /opt/ansible

chown -R ubuntu:ubuntu /opt/ansible


# ============================================================
# BASIC ANSIBLE CONFIG
# ============================================================

cat > /etc/ansible/ansible.cfg <<EOF
[defaults]
host_key_checking = False
inventory = /opt/ansible/inventory
roles_path = /opt/ansible/roles
retry_files_enabled = False
interpreter_python = auto_silent

[ssh_connection]
pipelining = True
EOF


# ============================================================
# HOSTNAME
# ============================================================

hostnamectl set-hostname ansible-controller


# ============================================================
# VERIFY INSTALLATION
# ============================================================

echo "========================================"
echo "Ansible Controller Versions"
echo "========================================"

ansible --version
aws --version
python3 --version

echo "========================================"
echo "Ansible controller setup completed."
echo "========================================"