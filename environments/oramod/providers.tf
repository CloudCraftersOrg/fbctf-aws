provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "fbctf-demo"
      Env       = "oramod"
      Owner     = var.owner
      ManagedBy = "terraform"
    }
  }
}
