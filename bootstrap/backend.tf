terraform {
  backend "s3" {
    bucket       = "image-service-tfstate-10-2026"
    key          = "bootstrap/terraform.tfstate"
    region       = "eu-north-1"
    encrypt      = true
    use_lockfile = true
  }
}