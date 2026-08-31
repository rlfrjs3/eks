resource "aws_ecr_repository" "app" {
  name = "${var.project_name}-app"

  image_scanning_configuration { scan_on_push = true }

  image_tag_mutability = "MUTABLE"
  force_delete         = true #ECR에 이미지가 남아있어도 강제 삭제

  tags = { Name = "${var.project_name}-app" }
}


