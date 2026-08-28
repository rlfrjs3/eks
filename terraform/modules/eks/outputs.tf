output "eks_cluster_name" { value = aws_eks_cluster.eks_cluster.name }
output "oidc_issuer_url" { value = aws_eks_cluster.eks_cluster.identity[0].oidc[0].issuer }
