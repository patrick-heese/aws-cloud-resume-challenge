output "site_bucket" {
  description = "S3 bucket name for the website"
  value       = aws_s3_bucket.site.id
}

output "cloudfront_distribution_id" {
  description = "CloudFront distribution ID for the website"
  value       = aws_cloudfront_distribution.site.id
}

output "cloudfront_domain_name" {
  description = "CloudFront distribution domain name (e.g., d123.cloudfront.net)"
  value       = aws_cloudfront_distribution.site.domain_name
}

output "ssm_api_param" {
  description = "SSM Parameter name that stores the API base URL"
  value       = aws_ssm_parameter.api.name
}
