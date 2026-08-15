variable "aws_region" {
  description = "S3バケットを作るリージョン(CloudFrontはグローバルサービスなので影響しない)"
  type        = string
  default     = "ap-northeast-1"
}

variable "bucket_name" {
  description = "Flutter Webビルド成果物を置くS3バケット名(全世界で一意である必要がある)"
  type        = string
}

variable "gemini_api_key" {
  description = "Gemini APIキー"
  type        = string
  sensitive   = true
}
