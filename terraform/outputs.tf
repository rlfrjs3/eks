output "eks_cluster_name" { value = module.eks.cluster_name }
output "vpc_id" { value = module.vpc.vpc_id }
output "aws_lb_controller_role_arn" { value = module.iam.aws_lb_controller_role_arn }
