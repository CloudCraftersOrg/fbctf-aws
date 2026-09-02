provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "fbctf-demo"
      Env       = "discovery-collector"
      Owner     = var.owner
      ManagedBy = "terraform"
    }
  }
}
