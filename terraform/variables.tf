variable "project_name" {
  description = "Short project string used in names"
  type        = string
  default     = "crc"
}

variable "region" {
  description = "AWS region for resources"
  type        = string
  default     = "us-east-1"
}

# Route 53 + custom domain (optional)
variable "enable_route53" {
  description = "Enable Route 53 + ACM for custom domain"
  type        = bool
  default     = false
}

variable "domain_name" {
  description = "Resume hostname, e.g., resume.firstnamelastname.com"
  type        = string
  default     = ""
}

variable "hosted_zone_id" {
  description = "Hosted zone ID for the ROOT domain that contains the resume subdomain"
  type        = string
  default     = ""
}

# CORS origins (API Gateway)
variable "include_cloudfront_origin" {
  description = "Also allow the CloudFront default domain during cutover/testing"
  type        = bool
  default     = true
}

variable "frontend_dev_origins" {
  description = "Optional dev origins (e.g., http://localhost:5173)"
  type        = list(string)
  default     = []
}

# Visitor counter partition key
variable "site_id" {
  description = "DynamoDB partition key value for the visitor counter"
  type        = string
  default     = "global"
}

# Tagging
variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default = {
    Project = "CloudResumeChallenge"
  }
}

# WAF
variable "enable_waf" {
  description = "Attach AWS WAFv2 to the CloudFront distribution"
  type        = bool
  default     = true
}

variable "waf_rate_limit" {
  description = "Requests per 5 minutes per IP before block (rate-based rule)"
  type        = number
  default     = 2000
}

variable "waf_enable_ip_reputation" {
  description = "Enable AWSManagedRulesAmazonIpReputationList"
  type        = bool
  default     = true
}

variable "waf_enable_anonymous_ip" {
  description = "Enable AWSManagedRulesAnonymousIpList"
  type        = bool
  default     = true
}
