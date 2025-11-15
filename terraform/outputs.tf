output "site_bucket" {
  value = aws_s3_bucket.site.id
}

output "cloudfront_domain" {
  value = aws_cloudfront_distribution.site.domain_name
}

output "api_base_url" {
  value = aws_apigatewayv2_stage.default.invoke_url
}

output "ssm_api_param" {
  value = aws_ssm_parameter.api_base_url.name
}

output "acm_certificate_arn" {
  value       = try(aws_acm_certificate_validation.validated[0].certificate_arn, null)
  description = "Present only when enable_route53 = true"
}
