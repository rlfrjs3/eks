###<각 모듈별 변수 참조>



module "network" {
  source               = "./modules/network"
  project_name         = var.project_name
  vpc_cidr             = var.vpc_cidr
  availability_zones   = var.availability_zones
  public_subnet_cidrs  = var.public_subnet_cidrs
  private_subnet_cidrs = var.private_subnet_cidrs
}

module "iam" {
  source              = "./modules/iam"
  project_name        = var.project_name
  eks_cluster_name    = module.eks.eks_cluster_name
  eks_oidc_issuer_url = module.eks.oidc_issuer_url
}

module "eks" {
  source               = "./modules/eks"
  project_name         = var.project_name
  private_subnet_ids   = module.network.private_subnet_ids
  eks_cluster_role_arn = module.iam.eks_cluster_role_arn
  eks_node_role_arn    = module.iam.eks_node_role_arn
}

module "ecr" {
  source       = "./modules/ecr"
  project_name = var.project_name
}
