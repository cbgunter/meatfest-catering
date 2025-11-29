#!/bin/bash
# Troubleshoot CloudFront Access Denied Issues

echo "🔍 CloudFront Access Denied Troubleshooter"
echo "=========================================="
echo ""

# Check if AWS CLI is available
command -v aws >/dev/null 2>&1 || { echo "❌ AWS CLI not installed"; exit 1; }

# Get inputs
read -p "Enter your S3 bucket name: " BUCKET_NAME
read -p "Enter your CloudFront distribution ID (e.g., E1234ABCD): " DIST_ID

echo ""
echo "Checking configuration..."
echo ""

# 1. Check if bucket exists and has files
echo "1️⃣ Checking S3 bucket contents..."
FILE_COUNT=$(aws s3 ls s3://$BUCKET_NAME/ --recursive | wc -l)
echo "   Files in bucket: $FILE_COUNT"

if [ "$FILE_COUNT" -eq 0 ]; then
    echo "   ⚠️  WARNING: Bucket is empty! Upload your site files first."
    echo ""
    read -p "   Upload files now? (y/n): " UPLOAD
    if [ "$UPLOAD" = "y" ]; then
        echo "   Uploading files..."
        aws s3 sync . s3://$BUCKET_NAME \
          --exclude ".git/*" \
          --exclude ".github/*" \
          --exclude "infra/*" \
          --exclude "scripts/*" \
          --exclude "*.md" \
          --exclude "assets/js/config.example.js"
        echo "   ✓ Files uploaded"
    fi
fi

# 2. Get CloudFront origin configuration
echo ""
echo "2️⃣ Checking CloudFront configuration..."
DIST_CONFIG=$(aws cloudfront get-distribution --id $DIST_ID 2>&1)

if echo "$DIST_CONFIG" | grep -q "NoSuchDistribution"; then
    echo "   ❌ Distribution not found. Check the ID: $DIST_ID"
    exit 1
fi

# Check origin
ORIGIN=$(echo "$DIST_CONFIG" | grep -o '"DomainName": "[^"]*"' | head -1 | cut -d'"' -f4)
echo "   Origin: $ORIGIN"

# Check if using OAC
OAC_ID=$(echo "$DIST_CONFIG" | grep -o '"OriginAccessControlId": "[^"]*"' | head -1 | cut -d'"' -f4)

if [ -n "$OAC_ID" ] && [ "$OAC_ID" != "null" ]; then
    echo "   Using Origin Access Control (OAC): $OAC_ID"
    USE_OAC=true
else
    echo "   No OAC configured"
    USE_OAC=false
fi

# 3. Get CloudFront ARN and generate bucket policy
echo ""
echo "3️⃣ Generating bucket policy..."

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
DIST_ARN="arn:aws:cloudfront::$ACCOUNT_ID:distribution/$DIST_ID"

if [ "$USE_OAC" = true ]; then
    # Policy for OAC
    cat > /tmp/bucket-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowCloudFrontServicePrincipal",
      "Effect": "Allow",
      "Principal": {
        "Service": "cloudfront.amazonaws.com"
      },
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::$BUCKET_NAME/*",
      "Condition": {
        "StringEquals": {
          "AWS:SourceArn": "$DIST_ARN"
        }
      }
    }
  ]
}
EOF
    echo "   Created OAC-based policy"
else
    # Public policy (not recommended but works)
    cat > /tmp/bucket-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::$BUCKET_NAME/*"
    }
  ]
}
EOF
    echo "   Created public policy (WARNING: Less secure)"
fi

# 4. Apply bucket policy
echo ""
echo "4️⃣ Applying bucket policy..."
echo ""
cat /tmp/bucket-policy.json
echo ""

read -p "Apply this policy to S3 bucket? (y/n): " APPLY
if [ "$APPLY" = "y" ]; then
    # Disable block public access if needed
    if [ "$USE_OAC" = false ]; then
        echo "   Disabling block public access..."
        aws s3api put-public-access-block \
          --bucket $BUCKET_NAME \
          --public-access-block-configuration \
            "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false" 2>/dev/null || true
    fi

    aws s3api put-bucket-policy --bucket $BUCKET_NAME --policy file:///tmp/bucket-policy.json
    echo "   ✓ Bucket policy applied"
else
    echo "   Policy NOT applied. You can apply it manually:"
    echo "   aws s3api put-bucket-policy --bucket $BUCKET_NAME --policy file:///tmp/bucket-policy.json"
fi

# 5. Test access
echo ""
echo "5️⃣ Testing CloudFront access..."
CLOUDFRONT_DOMAIN=$(aws cloudfront get-distribution --id $DIST_ID --query 'Distribution.DomainName' --output text)
echo "   CloudFront URL: https://$CLOUDFRONT_DOMAIN"

# Wait a moment for policy to propagate
echo "   Waiting 5 seconds for policy to propagate..."
sleep 5

# Test with curl
echo "   Testing with curl..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://$CLOUDFRONT_DOMAIN/index.html")

if [ "$HTTP_CODE" = "200" ]; then
    echo "   ✅ SUCCESS! Site is accessible"
    echo ""
    echo "   Visit: https://$CLOUDFRONT_DOMAIN"
elif [ "$HTTP_CODE" = "403" ]; then
    echo "   ❌ Still getting Access Denied (403)"
    echo ""
    echo "   Additional troubleshooting steps:"
    echo "   1. Wait 1-2 minutes for policy to fully propagate"
    echo "   2. Check CloudFront origin path is empty (not /public or similar)"
    echo "   3. Verify index.html exists in bucket root"
    echo "   4. Create invalidation: aws cloudfront create-invalidation --distribution-id $DIST_ID --paths '/*'"
elif [ "$HTTP_CODE" = "404" ]; then
    echo "   ⚠️  Getting 404 - file not found"
    echo "   Check that index.html exists in bucket root"
else
    echo "   Got HTTP code: $HTTP_CODE"
fi

echo ""
echo "📋 Summary:"
echo "   Bucket: $BUCKET_NAME"
echo "   Distribution: $DIST_ID"
echo "   Domain: https://$CLOUDFRONT_DOMAIN"
echo "   Files in bucket: $FILE_COUNT"
echo "   Using OAC: $USE_OAC"
echo ""
echo "Policy file saved to: /tmp/bucket-policy.json"
