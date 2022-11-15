### State Locking

terraform {
  backend "s3" {
    bucket         = "aws-stacks-terraform-state"
    key            = "web-hosting/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "aws-stacks-terraform-state-lock"
  }
}

### Create Website Files

resource "local_file" "aws-stacks-website-index" {
  filename = "${path.module}/index.html"
  content  = <<EOF
<!doctype html>
<html>
  <head>
    <title>Test - Static website</title>
  </head>
  <body style="background-color:lightgray;">
    <p><h1><center>Nice job!</center></h1></p>
    <p><h2><center>If you see this page, it means your static website is nicely configured!</center></h2></p>
  </body>
</html>
EOF
}

resource "local_file" "aws-stacks-website-error" {
  filename = "${path.module}/error.html"
  content  = <<EOF
<!doctype html>
<html>
  <head>
    <title>Test - Static website</title>
  </head>
  <body style="background-color:lightgray;">
    <p><h1><center>Error</center></h1></p>
    <p><h2><center>What you are looking for is not here, you should go this way instead: <a href="index.html">index.html</a></center></h2></p>
  </body>
</html>
EOF
}

### S3 resources

resource "aws_s3_bucket" "aws-stacks-s3-bucket" {
  bucket = "aws-stacks-web-hosting-s3-bucket"
}

resource "aws_s3_bucket_acl" "aws-stacks-s3-bucket-acl" {
  bucket = aws_s3_bucket.aws-stacks-s3-bucket.id
  acl    = "public-read"
}

resource "aws_s3_bucket_policy" "aws-stacks-s3-bucket-policy" {
  bucket = aws_s3_bucket.aws-stacks-s3-bucket.id
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "PublicReadGetObject",
            "Effect": "Allow",
            "Principal": "*",
            "Action": [
                "s3:GetObject"
            ],
            "Resource": [
                "arn:aws:s3:::${aws_s3_bucket.aws-stacks-s3-bucket.bucket}/*"
            ]
        }
    ]
}
EOF
}

resource "aws_s3_bucket_website_configuration" "aws-stacks-s3-bucket-web-conf" {
  bucket = aws_s3_bucket.aws-stacks-s3-bucket.id

  index_document {
    suffix = "index.html"
  }

  error_document {
    key = "error.html"
  }
}

resource "aws_s3_object" "aws-stacks-s3-object-index" {
  bucket       = aws_s3_bucket.aws-stacks-s3-bucket.id
  key          = "index.html"
  source       = "${path.module}/index.html"
  acl          = "public-read"
  content_type = "text/html"

  depends_on = [local_file.aws-stacks-website-index]
}

resource "aws_s3_object" "aws-stacks-s3-object-error" {
  bucket       = aws_s3_bucket.aws-stacks-s3-bucket.id
  key          = "error.html"
  source       = "${path.module}/error.html"
  acl          = "public-read"
  content_type = "text/html"

  depends_on = [local_file.aws-stacks-website-error]
}

### Add AWS Certificate Manager certificate

data "aws_acm_certificate" "aws-stacks-acm-certificate" {
  domain   = "aws-stacks.cif-project.com"
  statuses = ["ISSUED"]
}

### Cloudfront

resource "aws_cloudfront_distribution" "aws-stacks-cloudfront-distribution" {
  origin {
    domain_name = aws_s3_bucket.aws-stacks-s3-bucket.bucket_regional_domain_name
    origin_id   = "aws-stacks-origin"
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"
  aliases             = ["aws-stacks.cif-project.com"]
  price_class         = "PriceClass_100"

  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "aws-stacks-origin"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }


  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["US", "CA", "GB", "DE", "FR"]
    }
  }

  viewer_certificate {
    acm_certificate_arn = data.aws_acm_certificate.aws-stacks-acm-certificate.arn
    ssl_support_method  = "sni-only"
  }

  tags = {
    Name = "aws-stacks-cloudfront-distribution"
  }
}

### Route 53

# Add Hosted Zone

data "aws_route53_zone" "aws-stacks-route53-zone" {
  name         = "cif-project.com."
  private_zone = false
}

# Create DNS Record

resource "aws_route53_record" "aws-stacks-route53-record" {
  zone_id = data.aws_route53_zone.aws-stacks-route53-zone.zone_id
  name    = "aws-stacks.cif-project.com"
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.aws-stacks-cloudfront-distribution.domain_name
    zone_id                = aws_cloudfront_distribution.aws-stacks-cloudfront-distribution.hosted_zone_id
    evaluate_target_health = false
  }
}
