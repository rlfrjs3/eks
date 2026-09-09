# EKS OIDC / IRSA IAM 구성



## 1. IRSA (IAM Roles for Service Accounts)

IRSA는 EKS의 특정 Kubernetes ServiceAccount에 AWS IAM Role을 연결하여,
해당 ServiceAccount를 사용하는 Pod에만 필요한 AWS 권한을 부여하는 방식이다.

Worker Node의 IAM Role에 모든 AWS 권한을 부여하지 않고,
각 Pod가 수행하는 역할에 따라 최소한의 AWS 권한만 분리하여 부여할 수 있다.

### 사용 목적

현재 EKS 환경에서는 AWS 리소스를 제어해야 하는 Add-on에 각각 별도의 IAM Role을 구성하였다.

- VPC CNI
  - ServiceAccount : `kube-system/aws-node`
  - IAM Role : `eks-cni-role`
  - 권한 : ENI 및 Private IP 등 VPC 네트워크 리소스 관리

- AWS Load Balancer Controller
  - ServiceAccount : `kube-system/aws-load-balancer-controller`
  - IAM Role : `aws-lb-controller-role`
  - 권한 : ALB, Target Group 등 AWS Load Balancing 리소스 관리





## 2. OIDC (OpenID Connect)

IRSA에서 Kubernetes ServiceAccount의 신원을 AWS IAM이 신뢰할 수 있도록
EKS의 OIDC Issuer를 AWS IAM의 OIDC Provider로 등록한다.

EKS Cluster에는 고유한 OIDC Issuer URL이 존재한다.

예시:

https://oidc.eks.ap-northeast-2.amazonaws.com/id/XXXXXXXX

### OIDC Issuer

Issuer는 ServiceAccount Token을 발급한 주체를 의미한다.

Pod가 ServiceAccount를 사용하면 EKS는 해당 ServiceAccount의 신원 정보가 포함된
OIDC Token을 제공하며, AWS는 등록된 OIDC Provider를 통해 해당 Token이
신뢰할 수 있는 EKS Cluster에서 발급된 것인지 검증한다.

### OIDC Provider

EKS의 OIDC Issuer 정보를 AWS IAM에 등록한 리소스이다.

이를 통해 AWS IAM은 다음과 같은 ServiceAccount의 신원을 확인할 수 있다.

system:serviceaccount:<namespace>:<serviceaccount>

예:

system:serviceaccount:kube-system:aws-node





## 3. OIDC / IRSA를 이용한 IAM Role 구성

OIDC Provider를 통해 ServiceAccount의 신원을 검증하고,
IAM Role의 Trust Policy에서 해당 Role을 사용할 ServiceAccount를 제한한다.

예를 들어 VPC CNI의 IAM Role은 다음 ServiceAccount만 사용할 수 있도록 설정한다.

system:serviceaccount:kube-system:aws-node

전체 인증 및 권한 부여 흐름은 다음과 같다.

Pod
→ ServiceAccount
→ OIDC Token
→ AWS IAM OIDC Provider
→ IAM Role Trust Policy 검증
→ IAM Role Assume
→ IAM Permission Policy에 정의된 AWS 권한 사용

### Trust Policy

IAM Role을 **누가 사용할 수 있는지** 정의한다.

예:
VPC CNI IAM Role은 `kube-system/aws-node` ServiceAccount만 Assume할 수 있도록 제한한다.

### Permission Policy

IAM Role을 획득한 Pod가 **AWS에서 무엇을 할 수 있는지** 정의한다.

예:
VPC CNI IAM Role에는 `AmazonEKS_CNI_Policy`를 연결하여
VPC CNI가 ENI 및 Private IP 등의 AWS 네트워크 리소스를 관리할 수 있도록 한다.

따라서 최종적으로 다음과 같이 권한이 분리된다.

VPC CNI Pod
→ aws-node ServiceAccount
→ VPC CNI IAM Role
→ AmazonEKS_CNI_Policy
→ ENI / Private IP 관리

AWS Load Balancer Controller Pod
→ aws-load-balancer-controller ServiceAccount
→ LB Controller IAM Role
→ LB Controller IAM Policy
→ ALB / Target Group 등 관리
