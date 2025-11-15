project_name = "patrick-crc"
region       = "us-east-1"

# Custom domain (optional but recommended)
enable_route53 = true
domain_name    = "resume.patrickheese.com"
hosted_zone_id = "Z02030321HUP07V1WY2DI"

# During DNS propagation leave this true, then set to false later
include_cloudfront_origin = true

# Dev/test origins if you want
# frontend_dev_origins = ["http://localhost:5173"]

# WAF Settings
enable_waf               = true
waf_rate_limit           = 2000
waf_enable_ip_reputation = true
waf_enable_anonymous_ip  = true

# Counter partition key
site_id = "patrick-site"
