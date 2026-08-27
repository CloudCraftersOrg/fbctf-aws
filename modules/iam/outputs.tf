output "web_instance_profile_name" {
  value = aws_iam_instance_profile.tier["web"].name
}

output "app_instance_profile_name" {
  value = aws_iam_instance_profile.tier["app"].name
}

output "web_role_name" {
  value = aws_iam_role.tier["web"].name
}

output "app_role_name" {
  value = aws_iam_role.tier["app"].name
}
