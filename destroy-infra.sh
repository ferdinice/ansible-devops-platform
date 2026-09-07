#!/bin/bash
set -e

echo "========================================"
echo " Ansible DevOps Platform - DESTROY"
echo "========================================"

terraform init
terraform validate

terraform plan -destroy -out=destroy.tfplan

echo
echo "Destroy plan completed."
echo "Destroying infrastructure..."

terraform apply destroy.tfplan

rm -f destroy.tfplan

echo
echo "Infrastructure destroyed."