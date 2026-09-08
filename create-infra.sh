#!/bin/bash
set -euo pipefail

echo "========================================"
echo " Ansible DevOps Platform - CREATE"
echo "========================================"

PUBLIC_IP=$(curl -fsS https://checkip.amazonaws.com | tr -d '\r\n')
ALLOWED_CIDR="${PUBLIC_IP}/32"

echo "Using management CIDR: ${ALLOWED_CIDR}"

terraform init
terraform fmt -recursive
terraform validate

terraform plan \
  -var="allowed_cidr=${ALLOWED_CIDR}" \
  -out=tfplan

echo
echo "Terraform plan completed successfully."

read -r -p "Type APPLY to continue: " CONFIRMATION

if [ "$CONFIRMATION" != "APPLY" ]; then
  echo "Apply cancelled."
  rm -f tfplan
  exit 0
fi

terraform apply tfplan

rm -f tfplan

echo
echo "========================================"
echo " Infrastructure deployment completed."
echo "========================================"

terraform output