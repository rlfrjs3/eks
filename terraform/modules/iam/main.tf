###EKS 클러스터 Role 생성(현재는 안에 정책이 연결되지 않은 껍데기 상태) ->  EKS 클러스터 생성 시, 이 역할을 부여해서 만듬
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

###위에서 만든 Role에 아래 정책을 연결 -> AmazonEKSClusterPolicy : EKS Cluster가 AWS 리소스에 접근할 수 있도록
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}







###워커노드 Role 생성 (현재는 안에 정책이 연결되지 않은 껍데기 상태) -> 워커노드 그룹 생성 시, 이 역할을 부여해서 만듬
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

###위에서 만든 Role에 아래 정책 2개를 연결 -> AmazonEKSWorkerNodePolicy와 AmazonEC2ContainerRegistryPullOnly
#AmazonEKSWorkerNodePolicy : 워커노드가 EKS와 통신하기 위한 권한
#AmazonEC2ContainerRegistryPullOnly : 워커노드가 ECR에서 이미지를 pull해서 가져오기 위한 권한
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "ecr_pull_policy" {
  role       = aws_iam_role.eks_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPullOnly"
}








###################<VPC CNI가 띄워진 파드에서만 AmazonEKS_CNI_Policy 정책을 부여하기 위한 작업>################################

#EKS 클러스터의 OIDC Issuer 인증서 정보 조회
data "tls_certificate" "eks" {
  url = var.eks_oidc_issuer_url
}

#AWS IAM에 EKS OIDC Provider 등록
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


#인증이 됐으므로 이제 CNI Role에 연결할 Trust 정책(누가 사용할 지)  생성 ( kube-system 네임스페이스이고 aws-node serviceaccount 값을 가진 파드만 이 정책을 사용할 수 있음)
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


#CNI Role 생성하여 앞서 만든 신뢰 정책 할당 
resource "aws_iam_role" "eks_cni_role" {
  name = "${var.project_name}-eks-cni-role"

  assume_role_policy = data.aws_iam_policy_document.eks_cni_assume_role_policy.json
}


#추가로 AmazonEKS_CNI_Policy -> Permission 정책까지 연결
resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  role       = aws_iam_role.eks_cni_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}


#VPC CNI 애드온 서비스를 생성하는데 앞서 만든 CNI Role을 지정하여 생성
resource "aws_eks_addon" "vpc_cni" {
  cluster_name = var.eks_cluster_name
  addon_name   = "vpc-cni"

  service_account_role_arn = aws_iam_role.eks_cni_role.arn

  depends_on = [aws_iam_role_policy_attachment.eks_cni_policy]
}









###########<AWS LB 컨트롤러 파드가 AWS ALB (리스너, 타겟그룹)를 조회/생성/수정할 수 있도록 하기 위한 작업>#################

#AWS Load Balancer Controller가 AWS 리소스를 생성/조회/수정할 수 있도록 Permission Policy 생성
resource "aws_iam_policy" "aws_load_balancer_controller_policy" {
  name = "${var.project_name}-aws-load-balancer-controller-policy"

  policy = file("${path.module}/aws-load-balancer-controller-iam-policy.json")
}

#신뢰 정책 생성(kube-system 네임스페이스이고, serviceaccount는 aws-load-balancer-controller인 것만 파드만 사용 가능)
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

#iam Role을 만들고 신뢰 정책 붙이기
resource "aws_iam_role" "aws_load_balancer_controller_role" {
  name = "${var.project_name}-aws-load-balancer-controller-role"

  assume_role_policy = data.aws_iam_policy_document.aws_load_balancer_controller_assume_role_policy.json

  tags = {
    Name = "${var.project_name}-aws-load-balancer-controller-role"
  }
}

#마지막으로 맨 처음 만든 Permission Policy 붙이기 
resource "aws_iam_role_policy_attachment" "aws_load_balancer_controller_policy_attachment" {
  role       = aws_iam_role.aws_load_balancer_controller_role.name
  policy_arn = aws_iam_policy.aws_load_balancer_controller_policy.arn
}








###########<EBS CSI 컨트롤러 파드가 EBS를 자동 프로비저닝 할 수 있도록 하기 위한 작업>#################

# EBS CSI Driver IAM Role의 Trust Policy 생성
# kube-system 네임스페이스의 ebs-csi-controller-sa만
# 해당 IAM Role을 사용할 수 있도록 제한
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


# EBS CSI Driver 전용 IAM Role 생성
# 위 Trust Policy를 적용하여 EBS CSI Controller만 Role을 사용할 수 있도록 구성
resource "aws_iam_role" "ebs_csi_role" {
  name = "${var.project_name}-ebs-csi-role"

  assume_role_policy = data.aws_iam_policy_document.ebs_csi_assume_role_policy.json
}


# EBS CSI Driver가 EBS Volume 생성/삭제/연결 등의
# AWS API를 호출할 수 있도록 Permission Policy 연결
resource "aws_iam_role_policy_attachment" "ebs_csi_policy" {
  role = aws_iam_role.ebs_csi_role.name

  policy_arn = "arn:aws:iam::aws:policy/AmazonEBSCSIDriverPolicyV2"
}


# AWS EBS CSI Driver를 EKS Add-on으로 설치
# 생성한 IAM Role을 ebs-csi-controller-sa에 연결하여 IRSA 구성
resource "aws_eks_addon" "ebs_csi" {
  cluster_name = var.eks_cluster_name
  addon_name   = "aws-ebs-csi-driver"

  service_account_role_arn = aws_iam_role.ebs_csi_role.arn

  depends_on = [
    aws_iam_role_policy_attachment.ebs_csi_policy
  ]
}
