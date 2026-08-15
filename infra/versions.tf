terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# S3+CloudFrontの構成そのものはどのリージョンでも作れるが、
# ACM証明書をCloudFrontで使う場合はus-east-1固定という制約があるため、
# 将来カスタムドメインを足すときに気付けるようこのコメントを残す。
provider "aws" {
  region = var.aws_region
}
