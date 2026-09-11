#EKS Cluster 생성
resource "aws_eks_cluster" "eks_cluster" {
  name     = "${var.project_name}-eks"
  role_arn = var.eks_cluster_role_arn

  #EKS는 AWS 관리형 서비스이기 때문에 AWS 관리하는 EKS CP가 내 VPC 내부 리소스와 통신할 수 있도록 EKS-managed ENI를 생성하는 것 (EKS를 내 VPC 사설망에 생성한다는 뜻이 아님)
  vpc_config {
    subnet_ids = var.private_subnet_ids
  }
}



#워커노드 그룹 생성
resource "aws_eks_node_group" "eks_node_group" {
  cluster_name    = aws_eks_cluster.eks_cluster.name
  node_group_name = "${var.project_name}-node-group"

  node_role_arn = var.eks_node_role_arn
  subnet_ids    = var.private_subnet_ids

  scaling_config {
    desired_size = 4
    min_size     = 3
    max_size     = 4
  }

  instance_types = ["t3.medium"]

  capacity_type = "ON_DEMAND"

  depends_on = [aws_eks_cluster.eks_cluster]
}






#############################################
########### EKS Managed Add-on ##############
#############################################



# VPC CNI 설치 - iam 모듈에서 만든 VPC CNI 전용 IAM Role 연결
resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.eks_cluster.name
  addon_name   = "vpc-cni"

  service_account_role_arn = var.eks_cni_role_arn
}



# AWS EBS CSI Driver 설치 - iam 모듈에서 만든 EBS CSI 전용 IAM Role 연결
resource "aws_eks_addon" "ebs_csi" {
  cluster_name = aws_eks_cluster.eks_cluster.name
  addon_name   = "aws-ebs-csi-driver"

  service_account_role_arn = var.ebs_csi_role_arn
}



# Pod Identity Agent 설치 - Pod Identity Agent에는 별도 Role이 필요하지 않고 워커노드 그룹 Role을 사용함 (해당 Role 에 있는 AmazonEKSWorkerNodePolicy 권한정책에 필요로 하는 권한이 다 있음)
resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name = aws_eks_cluster.eks_cluster.name
  addon_name   = "eks-pod-identity-agent"
}





################################################################
##### External Secrets Operator - Pod Identity Association #####
################################################################

#External Secrets Operator가 사용하는 ServiceAccount와 IAM 모듈에서 만든 전용 Role을 연결 - IRSA에서는 신뢰정책에 넣는 설정을 Pod Identity를 사용하면 Pod Identity Associate을 별도로 만들어줘야 함
resource "aws_eks_pod_identity_association" "external_secrets" {
  cluster_name    = aws_eks_cluster.eks_cluster.name
  namespace       = "external-secrets"
  service_account = "external-secrets"
  role_arn        = var.external_secrets_role_arn
}
