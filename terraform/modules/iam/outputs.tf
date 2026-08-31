output "eks_cluster_role_arn" { value = aws_iam_role.eks_cluster_role.arn }
output "eks_node_role_arn" { value = aws_iam_role.eks_node_role.arn }
output "aws_load_balancer_controller_role_arn" { value = aws_iam_role.aws_load_balancer_controller_role.arn }
