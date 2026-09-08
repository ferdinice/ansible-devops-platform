#!/bin/bash
set -euo pipefail

echo "========================================"
echo " Ansible DevOps Platform - DESTROY"
echo "========================================"

# Detect current public IPv4 address.
# Terraform still needs this variable to evaluate the Jenkins SG
# even though the infrastructure is being destroyed.
PUBLIC_IP=$(curl -fsS https://checkip.amazonaws.com | tr -d '\r\n')
ALLOWED_CIDR="${PUBLIC_IP}/32"

echo "Using management CIDR: ${ALLOWED_CIDR}"

terraform init
terraform validate

terraform plan \
  -destroy \
  -var="allowed_cidr=${ALLOWED_CIDR}" \
  -out=destroy.tfplan

echo
echo "Destroy plan completed."
echo "Review the plan above."
read -r -p "Type DESTROY to continue: " CONFIRMATION

if [ "$CONFIRMATION" != "DESTROY" ]; then
  echo "Destroy cancelled."
  rm -f destroy.tfplan
  exit 0
fi

terraform apply destroy.tfplan

rm -f destroy.tfplan

echo
echo "========================================"
echo " Infrastructure destroyed successfully."
echo "========================================"