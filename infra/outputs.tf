output "cloudfront_domain_name" {
  description = "サイトのURL(https://をつけてアクセスする)"
  value       = aws_cloudfront_distribution.web.domain_name
}

output "s3_bucket_name" {
  description = "flutter build web の中身をアップロードする先"
  value       = aws_s3_bucket.web.bucket
}

output "alb_dns_name" {
  description = "バックエンドAPIのURL(https://をつけてアクセスする)"
  value       = aws_lb.test.dns_name
}

output "cloudfront_distribution_id" {
  description = "キャッシュ無効化(aws cloudfront create-invalidation)で使うID"
  value       = aws_cloudfront_distribution.web.id
}

# alb_dns_name = "test-lb-tf-333920964.ap-northeast-1.elb.amazonaws.com"
# cloudfront_distribution_id = "E2FUQCA5TNXU95"
# cloudfront_domain_name = "d1csbn7x8rs5ry.cloudfront.net"
# s3_bucket_name = "srl-lol-web-yatuharo"
