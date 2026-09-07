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

module "jenkins" {
  source = "./module/jenkins"

  project_name = var.project_name
  vpc_id       = module.vpc.vpc_id
  subnet_id    = module.vpc.public_subnet_id
  key_name     = module.keypair.key_name

  allowed_cidr = var.allowed_cidr
}