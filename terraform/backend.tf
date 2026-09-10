# Remote state in S3. Bucket must exist before first init
# (bootstrap step documented in README). S3 native locking
# is used (no DynamoDB table required, TF >= 1.10) — if your
# Terraform is < 1.10, remove use_lockfile.
terraform {
  backend "s3" {
    bucket       = "sentinel-tfstate-darwhas"
    key          = "sentinel/terraform.tfstate"
    region       = "eu-west-2"
    encrypt      = true
    use_lockfile = true
  }
}
