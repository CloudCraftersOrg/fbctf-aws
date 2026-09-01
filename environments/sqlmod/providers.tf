provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "fbctf-demo"
      Env       = "sqlmod"
      Owner     = var.owner
      ManagedBy = "terraform"
    }
  }
}
