#!/bin/bash

set -euo pipefail

exec > >(tee /var/log/ansible-userdata.log | logger -t user-data -s 2>/dev/console) 2>&1

echo "========================================"
echo "Starting Ansible controller setup..."
echo "========================================"

export DEBIAN_FRONTEND=noninteractive
export AWS_DEFAULT_REGION="eu-west-3"


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
# Required by amazon.aws.aws_ec2 dynamic inventory
# ============================================================

apt-get install -y python3-boto3 python3-botocore


# ============================================================
# ANSIBLE AWS COLLECTION
# ============================================================

ansible-galaxy collection install amazon.aws


# ============================================================
# ANSIBLE DIRECTORY STRUCTURE
# ============================================================

mkdir -p \
  /opt/ansible/inventory \
  /opt/ansible/group_vars \
  /opt/ansible/playbooks \
  /opt/ansible/roles

chown -R ubuntu:ubuntu /opt/ansible


# ============================================================
# AWS EC2 DYNAMIC INVENTORY
# ============================================================

cat > /opt/ansible/inventory/aws_ec2.yml <<'INVENTORY'
plugin: amazon.aws.aws_ec2

regions:
  - eu-west-3

filters:
  tag:Project: ansible-devops-platform
  instance-state-name: running

hostnames:
  - private-ip-address

keyed_groups:
  - key: tags.Environment
    prefix: ""
    separator: ""

compose:
  ansible_host: private_ip_address
INVENTORY


# ============================================================
# ANSIBLE GROUP VARIABLES
# ============================================================

cat > /opt/ansible/group_vars/all.yml <<'GROUPVARS'
ansible_user: ubuntu
ansible_ssh_private_key_file: /home/ubuntu/.ssh/id_rsa
ansible_python_interpreter: /usr/bin/python3
GROUPVARS


# ============================================================
# RESTORE SSH PRIVATE KEY FROM SSM PARAMETER STORE
# ============================================================

install -d \
  -m 700 \
  -o ubuntu \
  -g ubuntu \
  /home/ubuntu/.ssh

echo "Retrieving Ansible SSH private key from SSM Parameter Store..."

aws ssm get-parameter \
  --name "/devops-platform/ssh/private-key" \
  --with-decryption \
  --region eu-west-3 \
  --query "Parameter.Value" \
  --output text \
  > /home/ubuntu/.ssh/id_rsa

chown ubuntu:ubuntu /home/ubuntu/.ssh/id_rsa
chmod 600 /home/ubuntu/.ssh/id_rsa


# ============================================================
# OWNERSHIP
# ============================================================

chown -R ubuntu:ubuntu /opt/ansible


# ============================================================
# BASIC ANSIBLE CONFIG
# ============================================================

mkdir -p /etc/ansible

cat > /etc/ansible/ansible.cfg <<'ANSIBLECFG'
[defaults]
host_key_checking = False
inventory = /opt/ansible/inventory/aws_ec2.yml
roles_path = /opt/ansible/roles
retry_files_enabled = False
interpreter_python = auto_silent

[ssh_connection]
pipelining = True
ANSIBLECFG


# ============================================================
# HOSTNAME
# ============================================================

hostnamectl set-hostname ansible-controller


# ============================================================
# VERIFY BOOTSTRAP
# ============================================================

echo "========================================"
echo "Ansible Controller Versions"
echo "========================================"

ansible --version
aws --version
python3 --version

echo "========================================"
echo "Checking generated Ansible files"
echo "========================================"

test -f /opt/ansible/inventory/aws_ec2.yml
test -f /opt/ansible/group_vars/all.yml
test -f /home/ubuntu/.ssh/id_rsa

echo "Dynamic inventory:"
sudo -u ubuntu ansible-inventory \
  -i /opt/ansible/inventory/aws_ec2.yml \
  --graph

echo "========================================"
echo "Ansible controller setup completed."
echo "========================================"
