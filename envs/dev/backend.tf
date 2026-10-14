terraform {
  backend "s3" {
    bucket       = "image-service-tfstate-10-2026"
    encrypt      = true
    use_lockfile = true
    region       = "eu-north-1"
    key          = "dev/terraform.tfstate"

  }
}