provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "fbctf-demo"
      Env       = "discovery-fleet"
      Owner     = var.owner
      ManagedBy = "terraform"
    }
  }
}
