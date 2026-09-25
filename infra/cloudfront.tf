resource "aws_cloudfront_origin_access_control" "web" {
  name                              = "${var.bucket_name}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# S3(Flutter Web)向けのSPAフォールバックをCloudFront Functionで実装する。
# 以前はcustom_error_response(403/404 -> index.html)で対応していたが、それはディストリビューション
# 全体に効いてしまい、/api/*経由でFlaskが返す本物の404/403(例: Riot IDが見つからない)まで
# index.html+200にすり替わってAPI側のエラーハンドリングを壊してしまう。
# viewer-requestの時点で「拡張子を持たないパス=SPAのクライアントサイドルート」とみなして
# index.htmlに書き換えることで、S3・ALBどちらのオリジンにもエラーコードを発生させない。
resource "aws_cloudfront_function" "spa_routing" {
  name    = "${var.bucket_name}-spa-routing"
  runtime = "cloudfront-js-2.0"
  comment = "SPA fallback for the S3 web origin: extension-less paths -> /index.html"
  publish = true
  code    = <<-EOT
    function handler(event) {
      var request = event.request;
      var uri = request.uri;

      // 最後のパスセグメントに"."があれば実ファイル(.js/.png/.json等)とみなしてそのまま。
      var lastSegment = uri.substring(uri.lastIndexOf('/') + 1);
      if (lastSegment.indexOf('.') !== -1) {
        return request;
      }

      request.uri = '/index.html';
      return request;
    }
  EOT
}

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

resource "aws_cloudfront_distribution" "web" {
  enabled             = true
  default_root_object = "index.html"

  origin {
    domain_name              = aws_s3_bucket.web.bucket_regional_domain_name
    origin_id                = "s3-web-origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.web.id
  }

  # ALBはHTTPリスナーのみでACM証明書もカスタムドメインも持たないため、
  # WebアプリをCloudFront(HTTPS)配下で配信するとブラウザがmixed contentとしてAPI通信を
  # ブロックしてしまう。/api/*だけこのオリジンに流し、CloudFront-ALB間はHTTPのまま、
  # ブラウザから見えるURLは常にhttps://<cloudfrontドメイン>に統一する。
  origin {
    domain_name = aws_lb.test.dns_name
    origin_id   = "alb-api-origin"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-web-origin"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.spa_routing.arn
    }
  }

  # 振り返り投稿・動画アップロードでPOST/PUTが必要、かつレスポンスはキャッシュしてはいけない
  # (毎回変わる動的なJSON)ため、CachingDisabledを使う。ヘッダー/クエリ文字列/ボディはそのまま
  # ALBのFlaskへ転送する(AllViewerExceptHostHeader = Hostヘッダー以外は全転送)。
  ordered_cache_behavior {
    path_pattern           = "/api/*"
    target_origin_id       = "alb-api-origin"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  # カスタムドメインはまだ使わないので、CloudFrontが自動発行するデフォルト証明書をそのまま使う。
  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
