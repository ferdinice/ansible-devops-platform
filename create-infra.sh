#!/bin/bash
set -e

echo "========================================"
echo " Ansible DevOps Platform - CREATE"
echo "========================================"

terraform init
terraform fmt -recursive
terraform validate

terraform plan -out=tfplan

echo
echo "Terraform plan completed successfully."
echo "Applying infrastructure..."

terraform apply tfplan

rm -f tfplan

echo
echo "Infrastructure deployment completed."
terraform output