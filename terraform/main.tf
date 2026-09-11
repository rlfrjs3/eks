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
  eks_oidc_issuer_url = module.eks.oidc_issuer_url
}

module "eks" {
  source               = "./modules/eks"
  project_name         = var.project_name
  private_subnet_ids   = module.network.private_subnet_ids
  eks_cluster_role_arn = module.iam.eks_cluster_role_arn
  eks_node_role_arn    = module.iam.eks_node_role_arn
  eks_cni_role_arn     = module.iam.eks_cni_role_arn
  ebs_csi_role_arn     = module.iam.ebs_csi_role_arn
  external_secrets_role_arn = module.iam.external_secrets_role_arn
}

module "ecr" {
  source       = "./modules/ecr"
  project_name = var.project_name
}






################################################################
##### External Secrets Operator - Pod Identity Association #####
################################################################


#resource "aws_eks_pod_identity_association" "external_secrets" {
#  cluster_name = module.eks.eks_cluster_name
#  namespace       = "external-secrets"      	     # External Secrets Operator가 설치될 네임스페이스
#  service_account = "external-secrets"   	     # External Secrets Operator Pod가 사용할 ServiceAccount
#  role_arn = module.iam.external_secrets_role_arn    # IAM  모듈에서 생성한 External Secrets Operator 전용 IAM Role
#}


