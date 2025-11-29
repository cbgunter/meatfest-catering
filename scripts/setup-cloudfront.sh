#!/bin/bash
set -e

# Configuration
BUCKET_NAME="${BUCKET_NAME:-meatfestcatering-site}"
DOMAIN_NAME="${DOMAIN_NAME:-meatfestcatering.com}"
CERT_ARN="${CERT_ARN}"  # Set this to your ACM certificate ARN

if [ -z "$CERT_ARN" ]; then
  echo "Error: CERT_ARN environment variable must be set"
  echo "Example: export CERT_ARN='arn:aws:acm:us-east-1:123456789012:certificate/abc123...'"
  exit 1
fi

echo "Creating CloudFront distribution for $DOMAIN_NAME..."
echo "S3 Bucket: $BUCKET_NAME"
echo "Certificate: $CERT_ARN"

# Create CloudFront distribution
cat > /tmp/cloudfront-config.json <<EOF
{
  "CallerReference": "meatfest-$(date +%s)",
  "Comment": "Meatfest Catering Website",
  "DefaultRootObject": "index.html",
  "Origins": {
    "Quantity": 1,
    "Items": [
      {
        "Id": "S3-$BUCKET_NAME",
        "DomainName": "$BUCKET_NAME.s3.amazonaws.com",
        "OriginAccessControlId": "REPLACE_WITH_OAC_ID",
        "S3OriginConfig": {
          "OriginAccessIdentity": ""
        }
      }
    ]
  },
  "DefaultCacheBehavior": {
    "TargetOriginId": "S3-$BUCKET_NAME",
    "ViewerProtocolPolicy": "redirect-to-https",
    "AllowedMethods": {
      "Quantity": 2,
      "Items": ["GET", "HEAD"],
      "CachedMethods": {
        "Quantity": 2,
        "Items": ["GET", "HEAD"]
      }
    },
    "ForwardedValues": {
      "QueryString": false,
      "Cookies": {
        "Forward": "none"
      }
    },
    "MinTTL": 0,
    "DefaultTTL": 86400,
    "MaxTTL": 31536000,
    "Compress": true
  },
  "CustomErrorResponses": {
    "Quantity": 1,
    "Items": [
      {
        "ErrorCode": 404,
        "ResponsePagePath": "/404.html",
        "ResponseCode": "404",
        "ErrorCachingMinTTL": 300
      }
    ]
  },
  "Aliases": {
    "Quantity": 2,
    "Items": ["$DOMAIN_NAME", "www.$DOMAIN_NAME"]
  },
  "ViewerCertificate": {
    "ACMCertificateArn": "$CERT_ARN",
    "SSLSupportMethod": "sni-only",
    "MinimumProtocolVersion": "TLSv1.2_2021"
  },
  "Enabled": true,
  "PriceClass": "PriceClass_100"
}
EOF

echo "Note: You'll need to create an Origin Access Control (OAC) first."
echo "Run this command in the AWS Console or CLI to create OAC, then update the distribution."
