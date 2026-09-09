# EKS OIDC / IRSA IAM 구성



## 1. IRSA (IAM Roles for Service Accounts)

IRSA는 EKS의 특정 Kubernetes ServiceAccount에 AWS IAM Role을 연결하여,
해당 ServiceAccount를 사용하는 Pod에만 필요한 AWS 권한을 부여하는 방식이다.

Worker Node의 IAM Role에 여러 AWS 권한을 한꺼번에 부여하는 대신,
AWS API 호출이 필요한 각 Pod 또는 Add-on별로 별도의 IAM Role을 구성하여
최소 권한 원칙(Least Privilege)에 따라 권한을 분리할 수 있다.

### 사용 목적

현재 EKS 환경에서는 AWS 리소스를 제어해야 하는 Add-on 및 Controller에 각각 별도의 IAM Role을 구성하였다.

* **VPC CNI**

  * ServiceAccount : `kube-system/aws-node`
  * IAM Role : `eks-cni-role`
  * Permission Policy : `AmazonEKS_CNI_Policy`
  * 역할 : ENI 및 Private IP 등 Pod 네트워크 구성을 위한 AWS 네트워크 리소스 관리

* **AWS Load Balancer Controller**

  * ServiceAccount : `kube-system/aws-load-balancer-controller`
  * IAM Role : `aws-load-balancer-controller-role`
  * Permission Policy : AWS Load Balancer Controller 전용 Custom Policy
  * 역할 : ALB, Listener, Target Group, Security Group 등 Load Balancing 관련 AWS 리소스 관리

* **AWS EBS CSI Driver**

  * ServiceAccount : `kube-system/ebs-csi-controller-sa`
  * IAM Role : `ebs-csi-role`
  * Permission Policy : `AmazonEBSCSIDriverPolicyV2`
  * 역할 : Kubernetes PVC 요청에 따라 EBS Volume을 생성/조회/삭제하고 Pod에 연결하기 위한 AWS 리소스 관리





## 2. OIDC (OpenID Connect)

IRSA에서는 Kubernetes ServiceAccount의 신원을 AWS가 확인할 수 있어야 한다.

이를 위해 EKS Cluster의 OIDC Issuer를 AWS IAM의 **OIDC Provider**로 등록한다.

EKS Cluster에는 고유한 OIDC Issuer URL이 존재한다.

예시: https://oidc.eks.ap-northeast-2.amazonaws.com/id/XXXXXXXX

### OIDC Issuer

Issuer는 OIDC Token을 발급한 주체를 의미한다.

Pod가 Kubernetes ServiceAccount를 사용하면 해당 ServiceAccount의 신원 정보가 포함된 Token을 사용할 수 있으며,
AWS는 이 Token의 Issuer 정보를 확인하여 어느 EKS Cluster에서 발급된 Token인지 검증한다.

Token에는 ServiceAccount의 신원을 나타내는 정보가 포함된다.

예: system:serviceaccount:kube-system:aws-node

### OIDC Provider

EKS Cluster의 OIDC Issuer를 AWS IAM에 등록한 리소스이다.

AWS IAM은 등록된 OIDC Provider를 통해
ServiceAccount Token이 신뢰하도록 설정된 EKS Cluster에서 발급된 Token인지 검증할 수 있다.

현재 프로젝트에서는 하나의 EKS OIDC Provider를 생성하고,
VPC CNI, AWS Load Balancer Controller, EBS CSI Driver가 공통으로 사용한다.





## 3. AWS STS (Security Token Service)

STS는 AWS에서 **임시 보안 자격 증명(Temporary Security Credentials)**을 발급하는 서비스이다.

IRSA에서는 Pod가 IAM Role의 Access Key를 직접 가지고 있는 것이 아니다.

대신 Pod가 사용하는 ServiceAccount의 OIDC Token을 AWS STS에 전달하고,
STS가 Token과 IAM Role의 Trust Policy를 검증한 후
해당 IAM Role에 대한 임시 자격 증명을 발급한다.

IRSA에서는 다음 API가 사용된다. -> sts:AssumeRoleWithWebIdentity

즉, Kubernetes ServiceAccount의 OIDC Token을 이용하여IAM Role을 Assume하는 방식이다.


<흐름>

Pod
  ↓
ServiceAccount
  ↓
OIDC Token
  ↓
AWS STS
  ↓
IAM Role Trust Policy 검증
  ↓
AssumeRoleWithWebIdentity
  ↓
임시 AWS 자격 증명 발급
  ↓
IAM Permission Policy에 정의된 AWS API 호출


따라서 Pod 내부에 장기간 사용하는 AWS Access Key / Secret Access Key를 직접 저장할 필요가 없다.





## 4. Trust Policy와 Permission Policy

IAM Role을 구성할 때는 **Trust Policy**와 **Permission Policy**를 구분해야 한다.


### Trust Policy

IAM Role을 **누가 Assume할 수 있는지** 정의한다.

IRSA에서는 EKS OIDC Provider를 Federated Principal로 지정하고,
OIDC Token의 `aud`, `sub` 값을 조건으로 사용하여 특정 ServiceAccount만 Role을 Assume하도록 제한한다.

예를 들어 VPC CNI IAM Role은 다음 ServiceAccount만 사용할 수 있도록 제한한다. - > system:serviceaccount:kube-system:aws-node


### Permission Policy

IAM Role을 Assume한 주체가 **AWS에서 무엇을 할 수 있는지** 정의한다.

예를 들어 VPC CNI IAM Role에는 다음 정책을 연결한다.

AmazonEKS_CNI_Policy

이를 통해 VPC CNI가 ENI 및 Private IP 등 Pod 네트워크 구성을 위해 필요한 AWS API를 호출할 수 있다.

즉, Permission Policy는 다음 질문에 대한 설정이다.

"이 IAM Role을 획득한 뒤 무엇을 할 수 있는가?"





## 5. VPC CNI IRSA 구성

VPC CNI는 EKS에서 Pod 네트워크를 구성하는 Add-on이다.

VPC CNI의 `aws-node` Pod는 EC2 API를 호출하여 ENI 및 Secondary Private IP 등의 네트워크 리소스를 관리해야 한다.

이를 위해 다음과 같이 IRSA를 구성한다.

VPC CNI Pod
  ↓
aws-node ServiceAccount
  ↓
OIDC Token
  ↓
AWS STS
  ↓
VPC CNI IAM Role Assume
  ↓
AmazonEKS_CNI_Policy
  ↓
ENI / Private IP 등 네트워크 리소스 관리

IAM Role의 Trust Policy에서는 다음 ServiceAccount만 Role을 Assume할 수 있도록 제한한다.

system:serviceaccount:kube-system:aws-node





## 6. AWS Load Balancer Controller IRSA 구성

AWS Load Balancer Controller는 Kubernetes Ingress 등의 리소스를 감지하여
AWS의 Load Balancing 관련 리소스를 생성하고 관리한다.

주요 관리 대상은 다음과 같다.

ALB
Listener
Listener Rule
Target Group
Security Group
Target 등록


구성 흐름은 다음과 같다.

AWS Load Balancer Controller Pod
  ↓
aws-load-balancer-controller ServiceAccount
  ↓
OIDC Token
  ↓
AWS STS
  ↓
LB Controller IAM Role Assume
  ↓
AWS Load Balancer Controller Permission Policy
  ↓
ALB / Listener / Target Group 등 관리

IAM Role의 Trust Policy에서는 다음 ServiceAccount만 Role을 Assume할 수 있도록 제한한다. -> system:serviceaccount:kube-system:aws-load-balancer-controller





## 7. AWS EBS CSI Driver IRSA 구성

AWS EBS CSI Driver는 Kubernetes에서 EBS Volume을 Persistent Volume으로 사용할 수 있도록 연결하는 CSI Driver이다.

현재 프로젝트에서는 MySQL StatefulSet의 데이터를 영구 저장하기 위해 사용한다.

Kubernetes의 PVC가 생성되면 StorageClass에 지정된 CSI Provisioner를 통해
EBS CSI Driver가 AWS API를 호출하여 EBS Volume을 동적으로 생성한다.

StorageClass에서는 다음 Provisioner를 사용한다.

ebs.csi.aws.com


전체 동작 흐름은 다음과 같다.

MySQL StatefulSet
  ↓
PVC 생성
  ↓
StorageClass
  ↓
provisioner: ebs.csi.aws.com
  ↓
EBS CSI Controller
  ↓
ebs-csi-controller-sa ServiceAccount
  ↓
OIDC Token
  ↓
AWS STS
  ↓
EBS CSI IAM Role Assume
  ↓
AmazonEBSCSIDriverPolicyV2
  ↓
EBS Volume 동적 생성
  ↓
PV 생성 및 PVC Binding
  ↓
MySQL Pod에 Volume Mount


IAM Role의 Trust Policy에서는 다음 ServiceAccount만 Role을 Assume할 수 있도록 제한한다. -> system:serviceaccount:kube-system:ebs-csi-controller-sa

EBS CSI Driver IAM Role에는 다음 AWS 관리형 Permission Policy를 연결한다. -> AmazonEBSCSIDriverPolicyV2

이를 통해 EBS CSI Controller가 EBS Volume 생성, 조회, 삭제, Attach/Detach 등에 필요한 AWS API를 호출할 수 있다.

EBS CSI Driver 자체는 Terraform의 `aws_eks_addon`을 통해 EKS Managed Add-on으로 설치한다.
