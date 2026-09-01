# Legacy operating systems, on purpose. Some AMIs are deprecated and need
# include_deprecated = true; Canonical / Red Hat could remove them entirely,
# in which case the matching host fails at launch (documented risk, same as
# ADR 001 for the fbctf Xenial image).

data "aws_ami" "ubuntu_xenial" {
  most_recent        = true
  owners             = ["099720109477"]
  include_deprecated = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

data "aws_ami" "rhel7" {
  most_recent        = true
  owners             = ["309956199498"]
  include_deprecated = true

  filter {
    name   = "name"
    values = ["RHEL-7.9_HVM-*-x86_64-*"]
  }
}

data "aws_ami" "rhel8" {
  most_recent = true
  owners      = ["309956199498"]

  filter {
    name   = "name"
    values = ["RHEL-8.*_HVM-*-x86_64-*"]
  }
  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }
}

data "aws_ami" "windows_2016" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2016-English-Full-Base-*"]
  }
}

data "aws_ami" "windows_2019" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2019-English-Full-Base-*"]
  }
}

# SQL Server Express is licence-free, so the two database hosts cost the same
# as a plain Windows box. The sqlservr process and SQL Server -> Aurora
# assessment routing are identical to Standard.
data "aws_ami" "windows_2019_sql_express" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2019-English-Full-SQL_2019_Express-*"]
  }
}
