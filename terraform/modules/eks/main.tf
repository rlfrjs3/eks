#EKS Cluster 생성
resource "aws_eks_cluster" "eks_cluster" {
  name     = "${var.project_name}-eks"
  role_arn = var.eks_cluster_role_arn

  #EKS는 AWS 관리형 서비스이기 때문에 AWS 관리하는 EKS CP가 내 VPC 내부 리소스와 통신할 수 있도록 EKS-managed ENI를 생성하는 것 (EKS를 내 VPC 사설망에 생성한다는 뜻이 아님)
  vpc_config {
    subnet_ids = var.private_subnet_ids
  }
}





#워커노드 그룹 
resource "aws_eks_node_group" "eks_node_group" {
  cluster_name    = aws_eks_cluster.eks_cluster.name
  node_group_name = "${var.project_name}-node-group"

  node_role_arn = var.eks_node_role_arn
  subnet_ids    = var.private_subnet_ids

  scaling_config {
    desired_size = 2
    min_size     = 2
    max_size     = 4
  }

  instance_types = ["t3.medium"]

  capacity_type = "ON_DEMAND"

  depends_on = [aws_eks_cluster.eks_cluster]
}
