provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "fbctf-demo"
      Env       = "estate"
      Owner     = var.owner
      ManagedBy = "terraform"
    }
  }
}
