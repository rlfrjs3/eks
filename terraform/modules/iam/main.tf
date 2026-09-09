#############################################
######## EKS Control Plane IAM Role #########
#############################################

# EKS CP가 사용할 IAM Role 생성 (신뢰정책 포함 : EKS(eks.amazonaws.com)가 이 Role을 assume할 수 있도록 허용)
resource "aws_iam_role" "eks_cluster_role" {
  name = "${var.project_name}-eks-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "eks.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = { Name = "${var.project_name}-eks-cluster-role" }
}

# 앞서 만든 EKS Control Plane IAM Role에 AWS 관리형 권한정책 연결
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}





#############################################
###### EKS Worker Node (EC2) IAM Role #######
#############################################

# EKS Worker Node가 사용할 IAM Role 생성 (신뢰정책 포함 : EC2(ec2.amazonaws.com)가 이 Role을 assume할 수 있도록 허용)
resource "aws_iam_role" "eks_node_role" {
  name = "${var.project_name}-eks-node-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "ec2.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = { Name = "${var.project_name}-eks-node-role" }
}

# 앞서 만든 EKS Worker Node IAM Role에 AmazonEKSWorkerNodePolicy AWS 관리형 권한정책 연결 -> 워커노드가 EKS Control Plane과 통신하기 위한 권한
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}
한
# 앞서 만든 EKS Worker Node IAM Role에 AmazonEC2ContainerRegistryPullOnly AWS 관리형 권한정책 연결 -> 워커노드가 ECR에서 이미지를 pull해서 가져오기 위한 권한
resource "aws_iam_role_policy_attachment" "ecr_pull_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
}





#############################################
##### EKS OIDC Provider (IRSA 인증 기반)#####
#############################################

# EKS 클러스터의 OIDC Issuer TLS 인증서 정보 조회 -> AWS IAM에 OIDC Provider를 등록할 때 필요
data "tls_certificate" "eks" {
  url = var.eks_oidc_issuer_url
}

# EKS 클러스터의 OIDC Issuer를 AWS IAM OIDC Provider로 등록 -> EKS ServiceAccount의 OIDC 토큰을 AWS STS가 신뢰할 수 있도록 하기 위한 IRSA 인증 기반 구성
resource "aws_iam_openid_connect_provider" "eks" {
  url = var.eks_oidc_issuer_url

  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = [
    data.tls_certificate.eks.certificates[0].sha1_fingerprint
  ]

  tags = {
    Name = "${var.project_name}-eks-oidc"
  }
}





#############################################
############## VPC CNI IRSA #################
#############################################

# VPC CNI 전용 IAM Role의 신뢰정책 생성 -> EKS OIDC Provider를 통해 인증된 EKS ServiceAccount 중 kube-system 네임스페이스의 aws-node ServiceAccount만 해당 IAM Role에 assume할 수 있도록 제한
# aud : STS를 대상으로 발급한 토큰인지 확인
# sub : 특정 네임스페이스 + ServiceAccount인지 확인
data "aws_iam_policy_document" "eks_cni_assume_role_policy" {
  statement {
    effect = "Allow"

    actions = [
      "sts:AssumeRoleWithWebIdentity"
    ]

    principals {
      type = "Federated"

      identifiers = [
        aws_iam_openid_connect_provider.eks.arn
      ]
    }

    condition {
      test = "StringEquals"

      variable = "${replace(
        aws_iam_openid_connect_provider.eks.url,
        "https://",
        ""
      )}:aud"

      values = [
        "sts.amazonaws.com"
      ]
    }

    condition {
      test = "StringEquals"

      variable = "${replace(
        aws_iam_openid_connect_provider.eks.url,
        "https://",
        ""
      )}:sub"

      values = [
        "system:serviceaccount:kube-system:aws-node"
      ]
    }
  }
}

# VPC CNI 전용 IAM Role 생성 (앞서 만든 신뢰정책을 적용)
resource "aws_iam_role" "eks_cni_role" {
  name = "${var.project_name}-eks-cni-role"

  assume_role_policy = data.aws_iam_policy_document.eks_cni_assume_role_policy.json
}

# VPC CNI IAM Role에 AmazonEKS_CNI_Policy AWS 관리형 권한정책 연결 -> VPC CNI가 Pod 네으퉈크 구성할 때, ENI 및 사설IP 등 EC2 네트워크 리소스를 관리할 수 있도록 권한
resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  role       = aws_iam_role.eks_cni_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# VPC CNI를 EKS Managed Add-on 으로 구성 
resource "aws_eks_addon" "vpc_cni" {
  cluster_name = var.eks_cluster_name
  addon_name   = "vpc-cni"

  service_account_role_arn = aws_iam_role.eks_cni_role.arn

  depends_on = [aws_iam_role_policy_attachment.eks_cni_policy]
}





#############################################
######## AWS LB Controller IRSA  ############
#############################################

# AWS LB Controller 전용 권한정책 생성 -> Controller가 ALB, 리스너, 타겟그룹, SG 등 필요한 AWS 리소스를 생성/조회/수정/삭제할 수 있도록 정의
resource "aws_iam_policy" "aws_load_balancer_controller_policy" {
  name = "${var.project_name}-aws-load-balancer-controller-policy"

  policy = file("${path.module}/aws-load-balancer-controller-iam-policy.json")
}

# AWS LB Controller 전용 신뢰정책 생성 -> EKS OID Provider를 통해 인증된 kube-system 네임스페이스의 aws-load-balancer-controller ServiceAccount만 해당 IAM Role에 Assume할 수 있도록 
data "aws_iam_policy_document" "aws_load_balancer_controller_assume_role_policy" {
  statement {
    effect = "Allow"

    actions = [
      "sts:AssumeRoleWithWebIdentity"
    ]

    principals {
      type = "Federated"

      identifiers = [
        aws_iam_openid_connect_provider.eks.arn #앞서 CNI 정책때 사용했던 OIDC 프로바이더 사용
      ]
    }

    condition {
      test = "StringEquals"

      variable = "${replace(
        aws_iam_openid_connect_provider.eks.url,
        "https://",
        ""
      )}:aud"

      values = [
        "sts.amazonaws.com"
      ]
    }

    condition {
      test = "StringEquals"

      variable = "${replace(
        aws_iam_openid_connect_provider.eks.url,
        "https://",
        ""
      )}:sub"

      values = [
        "system:serviceaccount:kube-system:aws-load-balancer-controller"
      ]
    }
  }
}

# AWS LB Controller 전용 IAM Role 생성하고 앞서 만든 신뢰정책 연결 
resource "aws_iam_role" "aws_load_balancer_controller_role" {
  name = "${var.project_name}-aws-load-balancer-controller-role"

  assume_role_policy = data.aws_iam_policy_document.aws_load_balancer_controller_assume_role_policy.json

  tags = {
    Name = "${var.project_name}-aws-load-balancer-controller-role"
  }
}

# 마지막으로 AWS LB Controller 전용 IAM Role에 권한정책 연결
resource "aws_iam_role_policy_attachment" "aws_load_balancer_controller_policy_attachment" {
  role       = aws_iam_role.aws_load_balancer_controller_role.name
  policy_arn = aws_iam_policy.aws_load_balancer_controller_policy.arn
}





#############################################
########## EBS CSI Driver IRSA  #############
#############################################

# EBS CSI Driver Controller 전용 신뢰정책 생성 -> EKS OIDC Provider를 통해 인증된 kube-system 네임스페이스의 ebs-csi-controller-sa ServiceAccount만 해당 IAM Role에 assume할 수 있도록
data "aws_iam_policy_document" "ebs_csi_assume_role_policy" {
  statement {
    effect = "Allow"

    actions = [
      "sts:AssumeRoleWithWebIdentity"
    ]

    principals {
      type = "Federated"

      identifiers = [
        aws_iam_openid_connect_provider.eks.arn
      ]
    }

    condition {
      test = "StringEquals"

      variable = "${replace(
        aws_iam_openid_connect_provider.eks.url,
        "https://",
        ""
      )}:aud"

      values = [
        "sts.amazonaws.com"
      ]
    }

    condition {
      test = "StringEquals"

      variable = "${replace(
        aws_iam_openid_connect_provider.eks.url,
        "https://",
        ""
      )}:sub"

      values = [
        "system:serviceaccount:kube-system:ebs-csi-controller-sa"
      ]
    }
  }
}

# EBS CSI Driver Controller 전용 IAM Role 생성하고 앞서 만든 신뢰정책 연결
resource "aws_iam_role" "ebs_csi_role" {
  name = "${var.project_name}-ebs-csi-role"

  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role_policy.json
}

# EBS CSI Driver Controller 전용 IAM Role에 AWS 관리형 권한정책AmazonEBSCSIDriverPolicyV2 연결 -> EBS CSI Controller가 PVC 요청에 따라 EBS 볼륨을 생성/조회/삭제/Attach/Detach하는데 필요한 AWS API 권한 제공
resource "aws_iam_role_policy_attachment" "ebs_csi_policy" {
  role = aws_iam_role.ebs_csi_role.name

  policy_arn = "arn:aws:iam::aws:policy/AmazonEBSCSIDriverPolicyV2"
}


# AWS EBS CSI Driver를 EKS Managed Add-on으로 설치
# 생성한 IAM Role을 ebs-csi-controller-sa에 연결하여 IRSA 구성공
resource "aws_eks_addon" "ebs_csi" {
  cluster_name = var.eks_cluster_name
  addon_name   = "aws-ebs-csi-driver"

  service_account_role_arn = aws_iam_role.ebs_csi_role.arn

  depends_on = [
    aws_iam_role_policy_attachment.ebs_csi_policy
  ]
}
