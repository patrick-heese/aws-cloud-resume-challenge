########################################
# Locals & Data sources
########################################
locals {
  site_bucket_name = "${var.project_name}-site-${data.aws_caller_identity.me.account_id}"
  table_name       = "${var.project_name}-visitors"
  lambda_name      = "${var.project_name}-counter"
  ssm_param_name   = "/${var.project_name}/apiBaseUrl"
  default_tags     = var.tags

  # CORS allowed origins (resume domain, optional CF domain, optional dev)
  cors_origins_raw = flatten([
    (var.enable_route53 && var.domain_name != "") ? ["https://${var.domain_name}"] : [],
    var.include_cloudfront_origin ? ["https://${aws_cloudfront_distribution.site.domain_name}"] : [],
    var.frontend_dev_origins
  ])

  cors_origins = length(local.cors_origins_raw) > 0 ? distinct(local.cors_origins_raw) : ["*"]
}

data "aws_caller_identity" "me" {}
data "aws_partition" "cur" {}

########################################
# S3 (private) + CloudFront (OAC)
########################################
resource "aws_s3_bucket" "site" {
  bucket = local.site_bucket_name
  tags   = local.default_tags
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_cloudfront_origin_access_control" "oac" {
  name                              = "${var.project_name}-oac"
  description                       = "OAC for ${aws_s3_bucket.site.bucket}"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

########################################
# Optional: ACM + Route 53 for custom domain
########################################
resource "aws_acm_certificate" "cert" {
  count             = var.enable_route53 ? 1 : 0
  domain_name       = var.domain_name
  validation_method = "DNS"
  tags              = local.default_tags
}

# DNS validation records (domain_validation_options is a set → use for_each)
resource "aws_route53_record" "cert_validation" {
  for_each = var.enable_route53 ? {
    for dvo in aws_acm_certificate.cert[0].domain_validation_options :
    dvo.domain_name => {
      name  = dvo.resource_record_name
      type  = dvo.resource_record_type
      value = dvo.resource_record_value
    }
  } : {}

  zone_id = var.hosted_zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.value]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "validated" {
  count                   = var.enable_route53 ? 1 : 0
  certificate_arn         = aws_acm_certificate.cert[0].arn
  validation_record_fqdns = [for r in values(aws_route53_record.cert_validation) : r.fqdn]
}

########################################
# AWS WAFv2 Web ACL (CloudFront/global) - us-east-1
########################################
resource "aws_wafv2_web_acl" "site" {
  count       = var.enable_waf ? 1 : 0
  name        = "${var.project_name}-waf"
  description = "WAF for ${var.project_name} CloudFront"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-waf"
    sampled_requests_enabled   = true
  }

  # 1) Core protections
  rule {
    name     = "AWS-AWSManagedRulesCommonRuleSet"
    priority = 1
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesCommonRuleSet"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "CommonRuleSet"
      sampled_requests_enabled   = true
    }
  }

  # 2) Known bad inputs
  rule {
    name     = "AWS-AWSManagedRulesKnownBadInputsRuleSet"
    priority = 2
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        vendor_name = "AWS"
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "KnownBadInputs"
      sampled_requests_enabled   = true
    }
  }

  # 3) IP reputation (toggleable)
  dynamic "rule" {
    for_each = var.waf_enable_ip_reputation ? [1] : []
    content {
      name     = "AWS-AWSManagedRulesAmazonIpReputationList"
      priority = 3
      override_action {
        none {}
      }
      statement {
        managed_rule_group_statement {
          vendor_name = "AWS"
          name        = "AWSManagedRulesAmazonIpReputationList"
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "IpReputation"
        sampled_requests_enabled   = true
      }
    }
  }

  # 4) Anonymous IPs / VPNs / Proxies (toggleable)
  dynamic "rule" {
    for_each = var.waf_enable_anonymous_ip ? [1] : []
    content {
      name     = "AWS-AWSManagedRulesAnonymousIpList"
      priority = 4
      override_action {
        none {}
      }
      statement {
        managed_rule_group_statement {
          vendor_name = "AWS"
          name        = "AWSManagedRulesAnonymousIpList"
        }
      }
      visibility_config {
        cloudwatch_metrics_enabled = true
        metric_name                = "AnonymousIp"
        sampled_requests_enabled   = true
      }
    }
  }

  # 5) Simple per-IP rate limit
  rule {
    name     = "RateLimit"
    priority = 10
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "RateLimit"
      sampled_requests_enabled   = true
    }
  }

  tags = local.default_tags
}

########################################
# CloudFront (serves the static site) + WAF attachment
########################################
resource "aws_cloudfront_distribution" "site" {
  enabled             = true
  comment             = "${var.project_name} static site"
  default_root_object = "index.html"

  # Answer on your custom hostname when Route 53 is enabled
  aliases = var.enable_route53 && var.domain_name != "" ? [var.domain_name] : []

  origin {
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_id                = aws_s3_bucket.site.id
    origin_access_control_id = aws_cloudfront_origin_access_control.oac.id
  }

  default_cache_behavior {
    target_origin_id       = aws_s3_bucket.site.id
    viewer_protocol_policy = "redirect-to-https"

    allowed_methods = ["GET", "HEAD"]
    cached_methods  = ["GET", "HEAD"]
    compress        = true

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  price_class = "PriceClass_100"

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = var.enable_route53 ? false : true
    acm_certificate_arn            = var.enable_route53 ? aws_acm_certificate_validation.validated[0].certificate_arn : null
    ssl_support_method             = var.enable_route53 ? "sni-only" : null
    minimum_protocol_version       = "TLSv1.2_2021"
  }

  # Attach WAF (only when enabled)
  web_acl_id = var.enable_waf ? aws_wafv2_web_acl.site[0].arn : null

  tags = local.default_tags
}

# S3 bucket policy allowing only CloudFront (OAC) to read
data "aws_iam_policy_document" "site_policy" {
  statement {
    sid = "AllowCloudFrontOACRead"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.site.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.site.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = data.aws_iam_policy_document.site_policy.json
}

# DNS alias to CloudFront (if using Route 53)
resource "aws_route53_record" "alias_a" {
  count   = var.enable_route53 ? 1 : 0
  zone_id = var.hosted_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "alias_aaaa" {
  count   = var.enable_route53 ? 1 : 0
  zone_id = var.hosted_zone_id
  name    = var.domain_name
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.site.domain_name
    zone_id                = aws_cloudfront_distribution.site.hosted_zone_id
    evaluate_target_health = false
  }
}

########################################
# DynamoDB counter table
########################################
resource "aws_dynamodb_table" "visitors" {
  name         = local.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"

  attribute {
    name = "pk"
    type = "S"
  }

  tags = local.default_tags
}

########################################
# Lambda + IAM (packages ../src/count_function/count_lambda.py)
########################################
data "archive_file" "lambda_zip" {
  type        = "zip"
  source_file = "${path.module}/../src/count_function/count_lambda.py"
  output_path = "${path.module}/lambda.zip"
}

data "aws_iam_policy_document" "lambda_trust" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda" {
  name               = "${var.project_name}-lambda-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
  tags               = local.default_tags
}

data "aws_iam_policy_document" "lambda_ddb_policy" {
  statement {
    actions   = ["dynamodb:GetItem", "dynamodb:UpdateItem"]
    resources = [aws_dynamodb_table.visitors.arn]
  }

  statement {
    actions   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["arn:${data.aws_partition.cur.partition}:logs:*:*:*"]
  }
}

resource "aws_iam_policy" "lambda_ddb" {
  name   = "${var.project_name}-lambda-ddb"
  policy = data.aws_iam_policy_document.lambda_ddb_policy.json
}

resource "aws_iam_role_policy_attachment" "lambda_attach" {
  role       = aws_iam_role.lambda.name
  policy_arn = aws_iam_policy.lambda_ddb.arn
}

resource "aws_lambda_function" "counter" {
  function_name = local.lambda_name
  role          = aws_iam_role.lambda.arn
  handler       = "count_lambda.handler"
  runtime       = "python3.12"
  filename      = data.archive_file.lambda_zip.output_path

  environment {
    variables = {
      TABLE_NAME = aws_dynamodb_table.visitors.name
      SITE_ID    = var.site_id
    }
  }

  tags = local.default_tags
}

########################################
# API Gateway HTTP API -> Lambda
########################################
resource "aws_apigatewayv2_api" "http" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_methods = ["GET"]
    allow_headers = ["content-type"]
    max_age       = 600
    allow_origins = local.cors_origins
  }

  tags = local.default_tags
}

resource "aws_apigatewayv2_integration" "lambda" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.counter.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "get_count" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "GET /count"
  target    = "integrations/${aws_apigatewayv2_integration.lambda.id}"
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "$default"
  auto_deploy = true
  tags        = local.default_tags
}

resource "aws_lambda_permission" "allow_apigw" {
  statement_id  = "AllowInvokeFromAPIGW"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.counter.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}

########################################
# SSM parameter for frontend config.json
########################################
resource "aws_ssm_parameter" "api_base_url" {
  name  = local.ssm_param_name
  type  = "String"
  value = aws_apigatewayv2_stage.default.invoke_url
  tags  = local.default_tags
}
