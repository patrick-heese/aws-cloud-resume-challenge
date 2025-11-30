terraform {
  backend "s3" {
    bucket       = "493233983993-crc-tfstate"
    key          = "cloud-resume/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
