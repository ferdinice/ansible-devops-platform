module "vpc" {
  source = "./module/vpc"

  project_name        = var.project_name
  vpc_cidr            = var.vpc_cidr
  public_subnet_cidr  = var.public_subnet_cidr
  private_subnet_cidr = var.private_subnet_cidr
  availability_zone   = var.availability_zone
}

module "keypair" {
  source = "./module/keypair"

  project_name = var.project_name
}