module "network" {
  source       = "./modules/network"
  vpc_cidr     = var.vpc_cidr
  aws_region   = var.aws_region
  project_name = var.project_name
}

module "security_group" {
  source             = "./modules/security_group"
  vpc_id             = module.network.vpc_id
  vpc_cidr           = var.vpc_cidr
  my_ip              = var.my_ip
  project_name       = var.project_name
}

module "compute" {
  source             = "./modules/compute"
  instance_type      = var.instance_type
  subnet_id          = module.network.public_subnet_id
  security_group_id  = module.security_group.security_group_id
  key_pair_name      = var.key_pair_name
  worker_count       = var.worker_count
  project_name       = var.project_name
}
