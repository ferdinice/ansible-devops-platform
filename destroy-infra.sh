#!/bin/bash
set -euo pipefail

echo "========================================"
echo " Ansible DevOps Platform - DESTROY"
echo "========================================"

terraform init
terraform validate

terraform plan \
  -destroy \
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