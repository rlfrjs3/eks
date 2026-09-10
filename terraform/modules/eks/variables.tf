variable "project_name" { type = string }
variable "private_subnet_ids" { type = list(string) }
variable "eks_cluster_role_arn" { type = string }
variable "eks_node_role_arn" { type = string }
variable "eks_cni_role_arn" { type = string }
variable "ebs_csi_role_arn" { type = string }

