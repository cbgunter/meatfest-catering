#!/bin/bash
# Quick deployment script for Meatfest Catering
# This script helps you deploy the site step-by-step

set -e

echo "🍖 Meatfest Catering - AWS Deployment Script"
echo "=============================================="
echo ""

# Check prerequisites
command -v aws >/dev/null 2>&1 || { echo "❌ AWS CLI not installed. Install from: https://aws.amazon.com/cli/"; exit 1; }
command -v sam >/dev/null 2>&1 || { echo "❌ SAM CLI not installed. Install from: https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html"; exit 1; }

echo "✓ AWS CLI found"
echo "✓ SAM CLI found"
echo ""

# Check AWS credentials
aws sts get-caller-identity >/dev/null 2>&1 || { echo "❌ AWS credentials not configured. Run: aws configure"; exit 1; }
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "✓ AWS credentials configured (Account: $ACCOUNT_ID)"
echo ""

# Get configuration
read -p "Enter your AWS region [us-east-1]: " AWS_REGION
AWS_REGION=${AWS_REGION:-us-east-1}

read -p "Enter your domain name (e.g., meatfestcatering.com): " DOMAIN_NAME
if [ -z "$DOMAIN_NAME" ]; then
    echo "❌ Domain name is required"
    exit 1
fi

read -p "Enter notification email (where form submissions go): " TO_EMAIL
if [ -z "$TO_EMAIL" ]; then
    echo "❌ Email is required"
    exit 1
fi

read -p "Enter sender email (must be SES-verified): " FROM_EMAIL
FROM_EMAIL=${FROM_EMAIL:-$TO_EMAIL}

BUCKET_NAME="${DOMAIN_NAME//\./-}-site"
STACK_NAME="meatfest-forms"

echo ""
echo "Configuration:"
echo "  Region: $AWS_REGION"
echo "  Domain: $DOMAIN_NAME"
echo "  S3 Bucket: $BUCKET_NAME"
echo "  Stack Name: $STACK_NAME"
echo "  Notification Email: $TO_EMAIL"
echo "  Sender Email: $FROM_EMAIL"
echo ""

read -p "Continue with deployment? (y/n): " CONFIRM
if [ "$CONFIRM" != "y" ]; then
    echo "Deployment cancelled"
    exit 0
fi

echo ""
echo "Step 1: Verifying SES Email Addresses"
echo "======================================="

aws ses verify-email-identity --email-address "$TO_EMAIL" --region $AWS_REGION 2>/dev/null || true
aws ses verify-email-identity --email-address "$FROM_EMAIL" --region $AWS_REGION 2>/dev/null || true

echo "✓ Verification emails sent to $TO_EMAIL and $FROM_EMAIL"
echo "⚠️  Check your inbox and click the verification links!"
echo ""
read -p "Press Enter after you've verified both emails..."

# Check verification status
TO_STATUS=$(aws ses get-identity-verification-attributes --identities "$TO_EMAIL" --region $AWS_REGION --query "VerificationAttributes.\"$TO_EMAIL\".VerificationStatus" --output text)
FROM_STATUS=$(aws ses get-identity-verification-attributes --identities "$FROM_EMAIL" --region $AWS_REGION --query "VerificationAttributes.\"$FROM_EMAIL\".VerificationStatus" --output text)

if [ "$TO_STATUS" != "Success" ] || [ "$FROM_STATUS" != "Success" ]; then
    echo "⚠️  Warning: Emails not fully verified yet"
    echo "  TO_EMAIL ($TO_EMAIL): $TO_STATUS"
    echo "  FROM_EMAIL ($FROM_EMAIL): $FROM_STATUS"
    echo ""
    read -p "Continue anyway? (y/n): " CONTINUE
    if [ "$CONTINUE" != "y" ]; then
        exit 1
    fi
fi

echo ""
echo "Step 2: Deploying SAM Backend"
echo "=============================="
cd infra

sam build

sam deploy \
  --stack-name $STACK_NAME \
  --region $AWS_REGION \
  --resolve-s3 \
  --no-confirm-changeset \
  --no-fail-on-empty-changeset \
  --capabilities CAPABILITY_IAM \
  --parameter-overrides \
    ToEmail=$TO_EMAIL \
    FromEmail=$FROM_EMAIL

API_URL=$(aws cloudformation describe-stacks \
  --stack-name $STACK_NAME \
  --region $AWS_REGION \
  --query 'Stacks[0].Outputs[?OutputKey==`ApiBaseUrl`].OutputValue' \
  --output text)

echo ""
echo "✓ Backend deployed successfully!"
echo "  API URL: $API_URL"

cd ..

echo ""
echo "Step 3: Creating S3 Bucket"
echo "=========================="

aws s3 mb s3://$BUCKET_NAME --region $AWS_REGION 2>/dev/null || echo "Bucket already exists"
echo "✓ S3 bucket: $BUCKET_NAME"

echo ""
echo "Step 4: Creating Frontend Config"
echo "================================="

cat > assets/js/config.js <<EOF
window.MEATFEST_CONFIG = {
  apiBaseUrl: "$API_URL"
};
EOF

echo "✓ Created assets/js/config.js with API URL"

echo ""
echo "Step 5: Uploading to S3"
echo "======================="

aws s3 sync . s3://$BUCKET_NAME \
  --exclude ".git/*" \
  --exclude ".github/*" \
  --exclude "infra/*" \
  --exclude "scripts/*" \
  --exclude "*.md" \
  --exclude "assets/js/config.example.js" \
  --cache-control "public, max-age=3600"

echo "✓ Site uploaded to S3"

echo ""
echo "=========================================="
echo "🎉 Deployment Complete!"
echo "=========================================="
echo ""
echo "Next Steps:"
echo ""
echo "1. Set up CloudFront for HTTPS:"
echo "   - Go to AWS Console → CloudFront → Create distribution"
echo "   - Origin: $BUCKET_NAME.s3.amazonaws.com"
echo "   - Follow guide in DEPLOYMENT.md"
echo ""
echo "2. Request ACM certificate for $DOMAIN_NAME (in us-east-1)"
echo ""
echo "3. Update DNS to point to CloudFront distribution"
echo ""
echo "4. Test forms at your domain!"
echo ""
echo "API Endpoint: $API_URL"
echo "S3 Bucket: s3://$BUCKET_NAME"
echo ""
echo "For detailed instructions, see DEPLOYMENT.md"
