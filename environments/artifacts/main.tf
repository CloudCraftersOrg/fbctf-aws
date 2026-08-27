# Standalone root for the artifacts bucket: it must SURVIVE `terraform
# destroy` of the demo stack (the vendored packages and prebuilt tarballs are
# the insurance against dead upstreams — §3.6). Destroy cycles only ever touch
# environments/demo.

terraform {
  required_version = ">= 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  backend "s3" {
    bucket       = "fbctf-demo-tfstate-337058058699-use1"
    key          = "fbctf-artifacts/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Project   = "fbctf-demo"
      Env       = "demo"
      Owner     = "davismar98"
      ManagedBy = "terraform"
    }
  }
}

module "artifacts" {
  source = "../../modules/artifacts"

  bucket_name = "fbctf-demo-artifacts-337058058699-use1"
}

output "bucket_name" {
  value = module.artifacts.bucket_name
}
