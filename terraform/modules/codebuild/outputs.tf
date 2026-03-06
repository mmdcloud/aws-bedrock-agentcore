output "project_name" {
  value = aws_codebuild_project.codebuild_project.name
}

output "arn" {
  value = aws_codebuild_project.codebuild_project.arn
}