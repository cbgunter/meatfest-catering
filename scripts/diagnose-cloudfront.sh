#!/bin/bash
# Detailed CloudFront + S3 Diagnostic Script
# This will help identify the exact issue

echo "🔍 CloudFront + S3 Detailed Diagnostics"
echo "========================================="
echo ""

# Get user inputs
read -p "S3 Bucket Name: " BUCKET
read -p "CloudFront Distribution ID: " DIST_ID
read -p "AWS Region [us-east-1]: " REGION
REGION=${REGION:-us-east-1}

echo ""
echo "Running diagnostics..."
echo ""

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>&1)
if [ $? -ne 0 ]; then
    echo "❌ AWS credentials not configured or invalid"
    echo "   Run: aws configure"
    exit 1
fi

echo "✓ AWS Account: $ACCOUNT_ID"
echo ""

# ============================================
# 1. CHECK S3 BUCKET
# ============================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1️⃣  S3 Bucket Check"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Check if bucket exists
aws s3 ls s3://$BUCKET/ >/dev/null 2>&1
if [ $? -ne 0 ]; then
    echo "❌ Cannot access bucket: $BUCKET"
    echo "   Either it doesn't exist or you don't have permissions"
    exit 1
fi

echo "✓ Bucket exists and accessible"

# Check for files
FILE_COUNT=$(aws s3 ls s3://$BUCKET/ --recursive 2>/dev/null | wc -l)
echo "   Files in bucket: $FILE_COUNT"

if [ "$FILE_COUNT" -eq 0 ]; then
    echo "❌ PROBLEM: Bucket is empty!"
    echo "   You need to upload your site files first."
    echo ""
    echo "   Run from your project directory:"
    echo "   aws s3 sync . s3://$BUCKET --exclude '.git/*' --exclude 'infra/*' --exclude '*.md'"
    exit 1
fi

# Check if index.html exists
aws s3 ls s3://$BUCKET/index.html >/dev/null 2>&1
if [ $? -eq 0 ]; then
    echo "✓ index.html found in bucket"
else
    echo "⚠️  WARNING: index.html not found in bucket root"
    echo "   Files found:"
    aws s3 ls s3://$BUCKET/ | head -10
fi

# Check Block Public Access
BPA=$(aws s3api get-public-access-block --bucket $BUCKET 2>&1)
if echo "$BPA" | grep -q "NoSuchPublicAccessBlockConfiguration"; then
    echo "✓ Block Public Access: Not configured (allows public access)"
    BPA_ENABLED=false
elif echo "$BPA" | grep -q '"BlockPublicPolicy": true'; then
    echo "⚠️  Block Public Access: ENABLED"
    BPA_ENABLED=true
else
    echo "✓ Block Public Access: Disabled"
    BPA_ENABLED=false
fi

# Get bucket policy
echo ""
echo "Checking bucket policy..."
POLICY=$(aws s3api get-bucket-policy --bucket $BUCKET --query Policy --output text 2>&1)

if echo "$POLICY" | grep -q "NoSuchBucketPolicy"; then
    echo "❌ PROBLEM: No bucket policy found!"
    echo "   CloudFront needs a bucket policy to access S3"
    HAS_POLICY=false
else
    echo "✓ Bucket policy exists"
    HAS_POLICY=true

    # Check if policy allows CloudFront
    if echo "$POLICY" | grep -q "cloudfront.amazonaws.com"; then
        echo "✓ Policy includes CloudFront service principal"
        POLICY_TYPE="OAC"
    elif echo "$POLICY" | grep -q '"Principal": "\*"'; then
        echo "✓ Policy allows public access"
        POLICY_TYPE="PUBLIC"
    else
        echo "⚠️  Policy exists but unclear type"
        POLICY_TYPE="UNKNOWN"
    fi

    echo ""
    echo "Current bucket policy:"
    echo "$POLICY" | jq '.' 2>/dev/null || echo "$POLICY"
fi

echo ""

# ============================================
# 2. CHECK CLOUDFRONT DISTRIBUTION
# ============================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "2️⃣  CloudFront Distribution Check"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Get distribution details
DIST=$(aws cloudfront get-distribution --id $DIST_ID 2>&1)

if echo "$DIST" | grep -q "NoSuchDistribution"; then
    echo "❌ Distribution not found: $DIST_ID"
    echo "   Check your distribution ID"
    exit 1
fi

echo "✓ Distribution found: $DIST_ID"

# Get status
STATUS=$(echo "$DIST" | jq -r '.Distribution.Status' 2>/dev/null)
echo "   Status: $STATUS"

# Get domain
CF_DOMAIN=$(echo "$DIST" | jq -r '.Distribution.DomainName' 2>/dev/null)
echo "✓ CloudFront Domain: $CF_DOMAIN"

# Check origin configuration
ORIGIN_DOMAIN=$(echo "$DIST" | jq -r '.Distribution.DistributionConfig.Origins.Items[0].DomainName' 2>/dev/null)
echo ""
echo "Origin Configuration:"
echo "   Domain: $ORIGIN_DOMAIN"

# Check if using website endpoint (WRONG)
if echo "$ORIGIN_DOMAIN" | grep -q "s3-website"; then
    echo "❌ PROBLEM: Using S3 website endpoint!"
    echo "   CloudFront should use REST endpoint: $BUCKET.s3.amazonaws.com"
    echo "   Current (wrong): $ORIGIN_DOMAIN"
    echo ""
    echo "   FIX: Update CloudFront origin to: $BUCKET.s3.amazonaws.com"
    ORIGIN_WRONG=true
else
    echo "✓ Using S3 REST endpoint (correct)"
    ORIGIN_WRONG=false
fi

# Check Origin Access Control
OAC_ID=$(echo "$DIST" | jq -r '.Distribution.DistributionConfig.Origins.Items[0].OriginAccessControlId' 2>/dev/null)

if [ "$OAC_ID" = "null" ] || [ -z "$OAC_ID" ]; then
    echo "⚠️  No Origin Access Control configured"
    echo "   Using: Public S3 or legacy OAI"
    USES_OAC=false
else
    echo "✓ Using Origin Access Control: $OAC_ID"
    USES_OAC=true
fi

# Get default root object
ROOT_OBJ=$(echo "$DIST" | jq -r '.Distribution.DistributionConfig.DefaultRootObject' 2>/dev/null)
echo "   Default Root Object: $ROOT_OBJ"

if [ "$ROOT_OBJ" != "index.html" ]; then
    echo "⚠️  WARNING: Default root object is not 'index.html'"
fi

echo ""

# ============================================
# 3. ANALYZE CONFIGURATION
# ============================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "3️⃣  Configuration Analysis"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

ISSUES_FOUND=0

if [ "$ORIGIN_WRONG" = true ]; then
    echo "❌ CRITICAL: CloudFront origin is using website endpoint"
    echo "   This won't work with OAC or private buckets"
    ((ISSUES_FOUND++))
fi

if [ "$HAS_POLICY" = false ]; then
    echo "❌ CRITICAL: No bucket policy configured"
    echo "   CloudFront cannot access S3 without policy"
    ((ISSUES_FOUND++))
fi

if [ "$USES_OAC" = true ] && [ "$BPA_ENABLED" = true ]; then
    echo "✓ Using OAC with Block Public Access enabled (secure setup)"
elif [ "$USES_OAC" = true ] && [ "$BPA_ENABLED" = false ]; then
    echo "⚠️  Using OAC but Block Public Access disabled (unnecessary)"
elif [ "$USES_OAC" = false ] && [ "$BPA_ENABLED" = true ]; then
    echo "❌ CRITICAL: Not using OAC but Block Public Access enabled"
    echo "   Either enable OAC or disable Block Public Access"
    ((ISSUES_FOUND++))
elif [ "$USES_OAC" = false ] && [ "$BPA_ENABLED" = false ]; then
    echo "⚠️  Public bucket setup (less secure but simpler)"
fi

if [ "$USES_OAC" = true ] && [ "$HAS_POLICY" = true ]; then
    # Check if policy has correct ARN
    DIST_ARN="arn:aws:cloudfront::$ACCOUNT_ID:distribution/$DIST_ID"
    if echo "$POLICY" | grep -q "$DIST_ARN"; then
        echo "✓ Bucket policy has correct distribution ARN"
    else
        echo "❌ CRITICAL: Bucket policy missing or wrong distribution ARN"
        echo "   Expected: $DIST_ARN"
        ((ISSUES_FOUND++))
    fi
fi

echo ""

# ============================================
# 4. TEST ACCESS
# ============================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "4️⃣  Access Testing"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "Testing CloudFront access..."
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "https://$CF_DOMAIN/index.html" 2>/dev/null)

echo "   HTTP Response Code: $HTTP_CODE"

if [ "$HTTP_CODE" = "200" ]; then
    echo "✅ SUCCESS! CloudFront is working!"
elif [ "$HTTP_CODE" = "403" ]; then
    echo "❌ Access Denied (403)"
    ((ISSUES_FOUND++))
elif [ "$HTTP_CODE" = "404" ]; then
    echo "❌ Not Found (404) - index.html missing or wrong path"
    ((ISSUES_FOUND++))
else
    echo "❌ Unexpected response: $HTTP_CODE"
    ((ISSUES_FOUND++))
fi

# Test S3 direct access (if public)
if [ "$BPA_ENABLED" = false ]; then
    echo ""
    echo "Testing S3 direct access..."
    S3_HTTP=$(curl -s -o /dev/null -w "%{http_code}" "https://$BUCKET.s3.amazonaws.com/index.html" 2>/dev/null)
    echo "   S3 Direct HTTP Code: $S3_HTTP"

    if [ "$S3_HTTP" = "200" ]; then
        echo "   ✓ S3 is publicly accessible"
    else
        echo "   ✗ S3 not publicly accessible (OK if using OAC)"
    fi
fi

echo ""

# ============================================
# 5. RECOMMENDATIONS
# ============================================
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "5️⃣  Recommendations"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ $ISSUES_FOUND -eq 0 ] && [ "$HTTP_CODE" = "200" ]; then
    echo "🎉 No issues found! Your CloudFront distribution is working correctly."
    echo ""
    echo "   Access your site at: https://$CF_DOMAIN"
    exit 0
fi

echo "Found $ISSUES_FOUND critical issue(s). Here's how to fix them:"
echo ""

# Generate fix commands
if [ "$HAS_POLICY" = false ] || ([ "$USES_OAC" = true ] && ! echo "$POLICY" | grep -q "$DIST_ARN"); then
    echo "📝 FIX #1: Apply correct bucket policy"
    echo ""

    if [ "$USES_OAC" = true ]; then
        echo "   Run these commands:"
        echo ""
        cat <<EOF
cat > /tmp/bucket-policy.json <<'POLICY'
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
      "Resource": "arn:aws:s3:::$BUCKET/*",
      "Condition": {
        "StringEquals": {
          "AWS:SourceArn": "arn:aws:cloudfront::$ACCOUNT_ID:distribution/$DIST_ID"
        }
      }
    }
  ]
}
POLICY

aws s3api put-bucket-policy --bucket $BUCKET --policy file:///tmp/bucket-policy.json
EOF
    else
        echo "   Run these commands:"
        echo ""
        cat <<EOF
# Disable Block Public Access
aws s3api put-public-access-block \\
  --bucket $BUCKET \\
  --public-access-block-configuration \\
    "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"

# Apply public bucket policy
cat > /tmp/bucket-policy.json <<'POLICY'
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::$BUCKET/*"
    }
  ]
}
POLICY

aws s3api put-bucket-policy --bucket $BUCKET --policy file:///tmp/bucket-policy.json
EOF
    fi
    echo ""
fi

if [ "$ORIGIN_WRONG" = true ]; then
    echo "📝 FIX #2: Update CloudFront origin"
    echo ""
    echo "   In AWS Console:"
    echo "   1. Go to CloudFront → Distributions → $DIST_ID"
    echo "   2. Origins tab → Select origin → Edit"
    echo "   3. Change Origin domain to: $BUCKET.s3.amazonaws.com"
    echo "   4. Save changes"
    echo ""
fi

if [ "$HTTP_CODE" != "200" ]; then
    echo "📝 FIX #3: Clear CloudFront cache"
    echo ""
    echo "   aws cloudfront create-invalidation --distribution-id $DIST_ID --paths '/*'"
    echo ""
fi

echo "After applying fixes:"
echo "   1. Wait 1-2 minutes for changes to propagate"
echo "   2. Run this script again to verify"
echo "   3. Test: https://$CF_DOMAIN"
echo ""

exit 1
