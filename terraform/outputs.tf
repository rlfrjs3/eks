output "eks_cluster_name" { value = module.eks.eks_cluster_name }
output "vpc_id" { value = module.network.vpc_id }
output "aws_lb_controller_role_arn" { value = module.iam.aws_load_balancer_controller_role_arn }
