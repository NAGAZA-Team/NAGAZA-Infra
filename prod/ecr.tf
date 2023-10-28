resource "aws_ecr_repository" "nagaza-backend-prod" {
  name                 = "nagaza-backend-prod"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }
}
