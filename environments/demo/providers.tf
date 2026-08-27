provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "fbctf-demo"
      Env       = var.env
      Owner     = var.owner
      ManagedBy = "terraform"
    }
  }
}
