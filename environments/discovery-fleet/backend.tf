terraform {
  backend "s3" {
    bucket       = "fbctf-demo-tfstate-337058058699-use1"
    key          = "fbctf-discovery-fleet/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
