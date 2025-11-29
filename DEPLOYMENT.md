# AWS Deployment & DNS Migration Guide

## Prerequisites
- AWS account with admin access
- Domain name (e.g., meatfestcatering.com)
- AWS CLI configured with credentials
- SAM CLI installed

---

## Step 1: Deploy the Backend (Forms API)

### 1.1 Verify SES Email Addresses

```bash
# Set your region
export AWS_REGION="us-east-1"

# Verify your notification email (where you receive form submissions)
aws ses verify-email-identity \
  --email-address your-business-email@example.com \
  --region $AWS_REGION

# Check your inbox and click the verification link
```

**Important:** If your SES is in sandbox mode, you must verify BOTH:
- The sender email (FROM_EMAIL)
- The recipient email (TO_EMAIL)

Or request production access: https://console.aws.amazon.com/ses → Account dashboard → Request production access

### 1.2 Deploy SAM Backend

```bash
cd infra

# Build
sam build

# Deploy (first time)
sam deploy --guided

# Answer the prompts:
# - Stack Name: meatfest-forms
# - AWS Region: us-east-1
# - Parameter ToEmail: your-notification@email.com
# - Parameter FromEmail: verified-sender@email.com
# - Allow SAM CLI IAM role creation: Y
# - FormFunction may not have authorization: Y
# - Save to samconfig.toml: Y
```

**Save the API URL from the output:**
```
Outputs
-----------------------------------------------------------------
Key                 ApiBaseUrl
Value               https://abc123xyz.execute-api.us-east-1.amazonaws.com
```

---

## Step 2: Set Up S3 + CloudFront for HTTPS

### Option 1: Using AWS Console (Easiest)

#### 2.1 Create S3 Bucket
1. Go to S3 Console → Create bucket
2. Name: `meatfestcatering-site` (or your preferred name)
3. Region: `us-east-1`
4. **Block Public Access:** Leave ENABLED (CloudFront will access it privately)
5. Create bucket

#### 2.2 Request SSL Certificate
1. Go to Certificate Manager (ACM) → Request certificate
2. **IMPORTANT:** Switch region to `us-east-1` (required for CloudFront)
3. Request public certificate
4. Add domain names:
   - `meatfestcatering.com`
   - `www.meatfestcatering.com`
5. Validation: DNS validation
6. Request certificate
7. Click "Create records in Route 53" (if using Route 53) OR manually add CNAME records to your DNS provider
8. Wait for validation (~5-30 minutes)

#### 2.3 Create CloudFront Distribution
1. Go to CloudFront → Create distribution
2. **Origin domain:** Select your S3 bucket `meatfestcatering-site`
3. **Origin access:** Origin access control settings (recommended)
   - Click "Create control setting" → Create
   - Name: `meatfest-oac` → Create
4. **Default root object:** `index.html`
5. **Viewer protocol policy:** Redirect HTTP to HTTPS
6. **Allowed HTTP methods:** GET, HEAD
7. **Cache policy:** CachingOptimized
8. **Custom SSL certificate:** Select your ACM certificate
9. **Alternate domain names (CNAMEs):** Add both:
   - `meatfestcatering.com`
   - `www.meatfestcatering.com`
10. **Custom error responses:** Add:
    - HTTP error code: 404
    - Response page path: `/404.html`
    - HTTP response code: 404
11. Create distribution

#### 2.4 Update S3 Bucket Policy
After creating CloudFront, AWS will show you a bucket policy to copy. Or use this:

1. Go to S3 → Your bucket → Permissions → Bucket policy
2. Click "Edit" and paste:

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
      "Resource": "arn:aws:s3:::meatfestcatering-site/*",
      "Condition": {
        "StringEquals": {
          "AWS:SourceArn": "arn:aws:cloudfront::YOUR_ACCOUNT_ID:distribution/YOUR_DISTRIBUTION_ID"
        }
      }
    }
  ]
}
```

Replace `YOUR_ACCOUNT_ID` and `YOUR_DISTRIBUTION_ID` with your actual values.

---

## Step 3: Configure GitHub Actions

### 3.1 Set Up AWS OIDC (Secure, No Access Keys Needed)

Follow the guide in `SETUP-OIDC.md` or use this quick version:

#### Create IAM OIDC Provider
```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

#### Create IAM Role for GitHub Actions

Create file: `/tmp/github-trust-policy.json`
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:YOUR_GITHUB_USERNAME/meatfest-catering:*"
        }
      }
    }
  ]
}
```

Replace `YOUR_ACCOUNT_ID` and `YOUR_GITHUB_USERNAME`.

```bash
# Create the role
aws iam create-role \
  --role-name GitHubActionsMeatfestRole \
  --assume-role-policy-document file:///tmp/github-trust-policy.json

# Attach permissions
aws iam attach-role-policy \
  --role-name GitHubActionsMeatfestRole \
  --policy-arn arn:aws:iam::aws:policy/AmazonS3FullAccess

aws iam attach-role-policy \
  --role-name GitHubActionsMeatfestRole \
  --policy-arn arn:aws:iam::aws:policy/CloudFrontFullAccess

aws iam attach-role-policy \
  --role-name GitHubActionsMeatfestRole \
  --policy-arn arn:aws:iam::aws:policy/AWSCloudFormationFullAccess

# For SAM deployments, create custom policy with Lambda, API Gateway, DynamoDB, SES permissions
# (See SETUP-OIDC.md for full policy)
```

### 3.2 Configure GitHub Repository Secrets & Variables

Go to your GitHub repo → Settings → Secrets and variables → Actions

#### **Secrets:**
- `AWS_OIDC_ROLE_ARN`: `arn:aws:iam::YOUR_ACCOUNT_ID:role/GitHubActionsMeatfestRole`
- `TO_EMAIL`: Your business notification email
- `FROM_EMAIL`: Your SES verified sender email

#### **Variables:**
- `AWS_REGION`: `us-east-1`
- `S3_BUCKET`: `meatfestcatering-site`
- `DISTRIBUTION_ID`: Your CloudFront distribution ID (e.g., `E1234ABCD5678`)
- `API_BASE_URL`: Your API Gateway URL from Step 1.2 (e.g., `https://abc123.execute-api.us-east-1.amazonaws.com`)
- `SAM_STACK_NAME`: `meatfest-forms`
- `SAM_BUCKET`: (Optional) Leave blank to auto-create, or create a bucket: `meatfest-sam-artifacts`

---

## Step 4: Deploy to AWS via GitHub Actions

### 4.1 Deploy Backend (SAM)
```bash
# From your local machine
git pull origin claude/migrate-to-aws-s3-012Pjmy1Zzv9YTdqBqiX8EJV
git checkout main
git merge claude/migrate-to-aws-s3-012Pjmy1Zzv9YTdqBqiX8EJV
git push origin main
```

This triggers `.github/workflows/deploy-infra.yml` → deploys Lambda/API Gateway/DynamoDB

### 4.2 Deploy Frontend (Static Site)
The push to `main` will also trigger `.github/workflows/deploy-site.yml` → uploads to S3 and invalidates CloudFront

---

## Step 5: Update DNS Records

### If using Route 53:
1. Go to Route 53 → Hosted zones → Select your domain
2. Create/Update A record:
   - Name: `@` (root domain)
   - Type: A - IPv4 address
   - Alias: Yes
   - Alias target: Select your CloudFront distribution
3. Create/Update A record for www:
   - Name: `www`
   - Type: A - IPv4 address
   - Alias: Yes
   - Alias target: Select your CloudFront distribution

### If using another DNS provider (GoDaddy, Namecheap, etc.):
1. Get CloudFront domain name: `d123abc456def.cloudfront.net`
2. Update DNS records:
   - **A record or CNAME for root:** Point to CloudFront domain
   - **CNAME for www:** Point to CloudFront domain

   Example:
   ```
   Type    Name    Value
   A       @       d123abc456def.cloudfront.net  (or use ALIAS if supported)
   CNAME   www     d123abc456def.cloudfront.net
   ```

**Note:** DNS propagation can take 5 minutes to 48 hours

---

## Step 6: Test Your Deployment

### 6.1 Test CloudFront URL
```bash
# Get CloudFront domain
aws cloudfront list-distributions \
  --query 'DistributionList.Items[?Aliases.Items!=`null`] | [0].DomainName' \
  --output text
```

Visit: `https://YOUR_DISTRIBUTION.cloudfront.net`

### 6.2 Test Forms
1. Visit your site
2. Go to "Request Catering"
3. Fill out and submit the form
4. Check both:
   - Your notification email (TO_EMAIL)
   - Customer auto-reply (to the email you entered in the form)

### 6.3 Test DynamoDB
```bash
aws dynamodb scan --table-name meatfest-leads-$(aws sts get-caller-identity --query Account --output text)-us-east-1 --max-items 5
```

---

## Step 7: Final Checklist

- [ ] ACM certificate validated
- [ ] CloudFront distribution deployed (status: Deployed)
- [ ] S3 bucket policy allows CloudFront access
- [ ] GitHub Actions configured with all secrets/variables
- [ ] SAM backend deployed successfully
- [ ] Static site deployed to S3
- [ ] DNS records updated to point to CloudFront
- [ ] HTTPS working on your custom domain
- [ ] Forms submitting successfully
- [ ] Emails arriving (notification + auto-reply)
- [ ] DynamoDB storing submissions

---

## Troubleshooting

### Forms not working
- Check browser console for errors
- Verify `assets/js/config.js` has correct `apiBaseUrl`
- Check API Gateway CORS settings
- Verify SES emails are verified

### 403 Forbidden on CloudFront
- Check S3 bucket policy includes CloudFront distribution ARN
- Verify CloudFront Origin Access Control is configured

### DNS not resolving
- Use `dig meatfestcatering.com` or `nslookup meatfestcatering.com` to check DNS
- Wait longer (DNS can take up to 48 hours)
- Clear browser cache

### GitHub Actions failing
- Check Actions logs for specific error
- Verify all secrets/variables are set correctly
- Ensure IAM role has correct permissions

---

## Cost Estimate

- **S3:** $0.50-1/month
- **CloudFront:** $1-2/month (1TB free for 12 months)
- **Lambda:** Free tier (~$0)
- **DynamoDB:** Free tier (~$0)
- **SES:** Free tier (62,000 emails/month)
- **Route 53:** $0.50/month per hosted zone + $0.40/million queries

**Total: ~$2-5/month** for a small catering business
