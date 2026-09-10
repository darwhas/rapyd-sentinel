$versions = @"
terraform {
  required_version = ">= 1.9"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.80"
    }
  }
}
"@

$versions | Out-File -Encoding utf8 terraform\modules\networking\versions.tf
$versions | Out-File -Encoding utf8 terraform\modules\peering\versions.tf
$versions | Out-File -Encoding utf8 terraform\modules\iam\versions.tf
$versions | Out-File -Encoding utf8 terraform\modules\eks\versions.tf