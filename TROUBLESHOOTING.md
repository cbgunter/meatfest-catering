# CloudFront Access Denied Troubleshooting

## Quick Fix (Most Common Issues)

### Issue: "Access Denied" when visiting CloudFront URL

This happens because CloudFront cannot access your S3 bucket. Here's how to fix it:

---

## Option 1: Automated Fix (Easiest)

Run the troubleshooting script:

```bash
chmod +x scripts/fix-cloudfront-access.sh
./scripts/fix-cloudfront-access.sh
```

This script will:
- Check if files are uploaded to S3
- Detect if you're using Origin Access Control (OAC)
- Generate the correct bucket policy
- Apply the policy and test access

---

## Option 2: Manual Fix

### Step 1: Verify Files Are in S3

```bash
# Check bucket contents
aws s3 ls s3://YOUR-BUCKET-NAME/ --recursive

# If empty, upload files
aws s3 sync . s3://YOUR-BUCKET-NAME \
  --exclude ".git/*" \
  --exclude ".github/*" \
  --exclude "infra/*" \
  --exclude "scripts/*" \
  --exclude "*.md"
```

### Step 2: Check CloudFront Origin Configuration

```bash
# Get distribution details
aws cloudfront get-distribution --id YOUR-DISTRIBUTION-ID > /tmp/cf-config.json

# Check origin settings
cat /tmp/cf-config.json | grep -A 10 "Origins"
```

**Important checks:**
- Origin domain should be: `YOUR-BUCKET-NAME.s3.amazonaws.com` (NOT the website endpoint)
- Origin path should be empty (or `/` at most)
- Check if Origin Access Control (OAC) is configured

### Step 3: Apply Correct Bucket Policy

#### If Using Origin Access Control (OAC) - RECOMMENDED

1. Get your distribution ARN:
```bash
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
DIST_ID="YOUR-DISTRIBUTION-ID"
echo "arn:aws:cloudfront::$ACCOUNT_ID:distribution/$DIST_ID"
```

2. Create bucket policy file (`/tmp/bucket-policy.json`):
```json
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
      "Resource": "arn:aws:s3:::YOUR-BUCKET-NAME/*",
      "Condition": {
        "StringEquals": {
          "AWS:SourceArn": "arn:aws:cloudfront::YOUR-ACCOUNT-ID:distribution/YOUR-DIST-ID"
        }
      }
    }
  ]
}
```

3. Apply policy:
```bash
aws s3api put-bucket-policy --bucket YOUR-BUCKET-NAME --policy file:///tmp/bucket-policy.json
```

4. **Keep Block Public Access ENABLED** (this is secure with OAC)

#### If NOT Using OAC (Less Secure)

1. Disable block public access:
```bash
aws s3api put-public-access-block \
  --bucket YOUR-BUCKET-NAME \
  --public-access-block-configuration \
    "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"
```

2. Create public bucket policy:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::YOUR-BUCKET-NAME/*"
    }
  ]
}
```

3. Apply:
```bash
aws s3api put-bucket-policy --bucket YOUR-BUCKET-NAME --policy file:///tmp/bucket-policy.json
```

### Step 4: Wait and Test

```bash
# Wait 1-2 minutes for policy to propagate
sleep 60

# Get CloudFront domain
DOMAIN=$(aws cloudfront get-distribution --id YOUR-DIST-ID --query 'Distribution.DomainName' --output text)

# Test
curl -I https://$DOMAIN/index.html
```

Should return: `HTTP/2 200`

---

## Using AWS Console (Visual Method)

### Fix via Console:

1. **Go to S3 Console** → Your bucket → **Permissions**

2. **Scroll to Bucket Policy** → Click **Edit**

3. **Paste this policy** (replace YOUR-BUCKET-NAME and YOUR-DIST-ARN):

   **For OAC (Recommended):**
   ```json
   {
     "Version": "2012-10-17",
     "Statement": [
       {
         "Effect": "Allow",
         "Principal": {
           "Service": "cloudfront.amazonaws.com"
         },
         "Action": "s3:GetObject",
         "Resource": "arn:aws:s3:::YOUR-BUCKET-NAME/*",
         "Condition": {
           "StringEquals": {
             "AWS:SourceArn": "arn:aws:cloudfront::ACCOUNT-ID:distribution/DIST-ID"
           }
         }
       }
     ]
   }
   ```

   **To get your distribution ARN:**
   - Go to CloudFront → Click your distribution
   - Copy the ARN from the top of the page
   - Format: `arn:aws:cloudfront::123456789012:distribution/E1234ABCD`

4. **Click Save**

5. **Test CloudFront URL** in browser

---

## Common Mistakes & Solutions

### ❌ Mistake 1: Using S3 Website Endpoint as Origin

**Wrong:**
```
Origin: YOUR-BUCKET.s3-website-us-east-1.amazonaws.com
```

**Correct:**
```
Origin: YOUR-BUCKET.s3.amazonaws.com
```

**Fix:** Update CloudFront origin domain name.

---

### ❌ Mistake 2: Block Public Access Enabled WITHOUT OAC

If you're NOT using OAC, you must disable Block Public Access.

**Fix:**
```bash
aws s3api put-public-access-block \
  --bucket YOUR-BUCKET \
  --public-access-block-configuration \
    "BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false"
```

---

### ❌ Mistake 3: Wrong Bucket Policy ARN Format

Make sure the ARN in your bucket policy matches EXACTLY:
```
arn:aws:cloudfront::YOUR-ACCOUNT-ID:distribution/YOUR-DIST-ID
```

Get it with:
```bash
aws sts get-caller-identity --query Account --output text  # Your account ID
aws cloudfront list-distributions --query 'DistributionList.Items[0].Id' --output text  # Dist ID
```

---

### ❌ Mistake 4: No Index.html in Bucket Root

Check if index.html exists:
```bash
aws s3 ls s3://YOUR-BUCKET/index.html
```

If missing, upload:
```bash
aws s3 cp index.html s3://YOUR-BUCKET/index.html
```

---

### ❌ Mistake 5: CloudFront Cache Showing Old Error

Create invalidation to clear cache:
```bash
aws cloudfront create-invalidation \
  --distribution-id YOUR-DIST-ID \
  --paths "/*"
```

Wait 1-5 minutes for invalidation to complete.

---

## Verification Checklist

After applying fixes, verify:

- [ ] Files exist in S3 bucket (check with `aws s3 ls`)
- [ ] Bucket policy is applied (check in S3 Console → Permissions)
- [ ] CloudFront origin is correct (s3.amazonaws.com, not website endpoint)
- [ ] If using OAC, policy has correct distribution ARN
- [ ] If NOT using OAC, Block Public Access is disabled
- [ ] CloudFront shows "Enabled" status
- [ ] Created invalidation (if you had errors before)
- [ ] Waited 1-2 minutes for policy to propagate
- [ ] Test URL returns 200 (not 403)

---

## Test Commands

```bash
# 1. Test CloudFront
curl -I https://YOUR-CLOUDFRONT-DOMAIN.cloudfront.net/index.html

# Should see: HTTP/2 200

# 2. Test specific file
curl https://YOUR-CLOUDFRONT-DOMAIN.cloudfront.net/index.html

# Should see HTML content

# 3. Check S3 directly (if public)
curl -I https://YOUR-BUCKET.s3.amazonaws.com/index.html

# May be 403 if using OAC (this is OK)
```

---

## Still Not Working?

### Check CloudFormation Events (if using SAM for CloudFront)

```bash
aws cloudformation describe-stack-events --stack-name YOUR-STACK-NAME --max-items 20
```

### Check CloudFront Error Logs

1. Go to CloudFront Console
2. Click your distribution
3. Go to **Monitoring** tab
4. Check for error rate spikes

### Enable CloudFront Logging

1. CloudFront Console → Your distribution → Edit
2. Scroll to **Standard logging**
3. Enable and select/create an S3 bucket for logs
4. Save and wait for logs to appear

### Get Help

If still stuck:
1. Check CloudFront distribution Origin settings in console
2. Verify S3 bucket region matches your expectations
3. Try creating a NEW test bucket with public policy to isolate the issue
4. Check AWS Support forums or contact AWS Support

---

## Pro Tip: Use OAC, Not Public Bucket

**Recommended Setup:**
- ✅ Use Origin Access Control (OAC)
- ✅ Keep S3 Block Public Access ENABLED
- ✅ Use bucket policy with CloudFront service principal
- ✅ This is more secure (bucket not publicly accessible)

**vs. Public Bucket:**
- ❌ Disable Block Public Access
- ❌ Anyone can access S3 bucket directly
- ❌ Less secure
- ✅ But easier to troubleshoot

Start with public for testing, then switch to OAC for production.
