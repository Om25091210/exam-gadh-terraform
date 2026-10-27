variable "name" { type = string }
variable "repositories" {
  type    = list(string)
  default = ["api", "web", "admin"]
}

resource "aws_ecr_repository" "this" {
  for_each             = toset(var.repositories)
  name                 = "${var.name}-${each.key}"
  image_tag_mutability = "IMMUTABLE" # deploy by git SHA; rollbacks pick an older tag
  force_delete         = false

  image_scanning_configuration { scan_on_push = true }
  encryption_configuration { encryption_type = "AES256" }
}

resource "aws_ecr_lifecycle_policy" "this" {
  for_each   = aws_ecr_repository.this
  repository = each.value.name
  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep the last 20 images"
      selection    = { tagStatus = "any", countType = "imageCountMoreThan", countNumber = 20 }
      action       = { type = "expire" }
    }]
  })
}

output "repository_arns" { value = { for k, r in aws_ecr_repository.this : k => r.arn } }
output "repository_urls" { value = { for k, r in aws_ecr_repository.this : k => r.repository_url } }
