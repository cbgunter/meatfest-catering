#!/bin/bash
# Meatfest Catering Deployment Script

set -e

echo "🔥 Meatfest Catering - Deployment Script 🔥"
echo ""

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if AWS CLI is configured
if ! aws sts get-caller-identity &> /dev/null; then
    echo "❌ AWS CLI is not configured or credentials are invalid"
    echo "Run: aws configure"
    exit 1
fi

echo -e "${BLUE}Finding S3 bucket...${NC}"
BUCKET=$(aws s3 ls | grep meatfest | awk '{print $3}' | head -1)

if [ -z "$BUCKET" ]; then
    echo "❌ No meatfest bucket found. Please provide bucket name:"
    read -p "S3 Bucket name: " BUCKET
fi

echo -e "${GREEN}✓ Using bucket: $BUCKET${NC}"
echo ""

echo -e "${BLUE}Finding CloudFront distribution...${NC}"
DIST_ID=$(aws cloudfront list-distributions --query "DistributionList.Items[?contains(Origins.Items[0].DomainName, '$BUCKET')].Id" --output text)

if [ -z "$DIST_ID" ]; then
    echo "⚠️  No CloudFront distribution found for this bucket."
    read -p "Enter CloudFront Distribution ID (or press Enter to skip): " DIST_ID
fi

if [ -n "$DIST_ID" ]; then
    echo -e "${GREEN}✓ Using distribution: $DIST_ID${NC}"
fi
echo ""

# Sync files to S3
echo -e "${BLUE}Uploading files to S3...${NC}"
aws s3 sync . s3://$BUCKET/ \
    --exclude ".git/*" \
    --exclude "infra/*" \
    --exclude "*.md" \
    --exclude ".gitignore" \
    --exclude "deploy.sh" \
    --exclude ".github/*" \
    --delete

echo -e "${GREEN}✓ Files uploaded successfully${NC}"
echo ""

# Invalidate CloudFront cache
if [ -n "$DIST_ID" ]; then
    echo -e "${BLUE}Invalidating CloudFront cache...${NC}"
    INVALIDATION_ID=$(aws cloudfront create-invalidation \
        --distribution-id $DIST_ID \
        --paths "/*" \
        --query 'Invalidation.Id' \
        --output text)

    echo -e "${GREEN}✓ Invalidation created: $INVALIDATION_ID${NC}"
    echo "Cache will be cleared in a few minutes."
else
    echo "⚠️  Skipping CloudFront invalidation (no distribution ID)"
fi

echo ""
echo -e "${GREEN}🎉 Deployment complete!${NC}"
echo ""
echo "Your site should be updated at: https://www.meatfestcatering.com"
echo "Forms are now configured and ready to use!"
