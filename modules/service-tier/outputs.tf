output "asg_name" {
  value = aws_autoscaling_group.this.name
}

output "ami_id" {
  value = data.aws_ami.xenial.id
}
