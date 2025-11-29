# AWS OIDC Setup for GitHub Actions

## Problem
GitHub Actions needs to authenticate to AWS using OIDC (OpenID Connect), but your AWS account doesn't have the GitHub OIDC provider registered yet.

## Solution: Create OIDC Provider (One-Time Setup)

### Step 1: Create the OIDC Provider in AWS

Run this in AWS CLI (or use the AWS Console):

```bash
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1
```

**Or via AWS Console:**
1. Go to IAM → Access management → Identity providers
2. Click "Add provider"
3. Provider type: OpenID Connect
4. Provider URL: `https://token.actions.githubusercontent.com`
5. Audience: `sts.amazonaws.com`
6. Click "Add provider"

### Step 2: Create IAM Role for GitHub Actions

Create a new IAM role with this trust policy (replace `YOUR_ACCOUNT_ID` with your AWS account ID):

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
          "token.actions.githubusercontent.com:sub": "repo:cbgunter/meatfest-catering:*"
        }
      }
    }
  ]
}
```

### Step 3: Attach Policies to the Role

The role needs permissions for:

**For Site Deployment:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::YOUR_BUCKET_NAME",
        "arn:aws:s3:::YOUR_BUCKET_NAME/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": "cloudfront:CreateInvalidation",
      "Resource": "*"
    }
  ]
}
```

**For Backend (SAM) Deployment:**
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "cloudformation:*",
        "s3:*",
        "lambda:*",
        "apigateway:*",
        "dynamodb:*",
        "iam:GetRole",
        "iam:CreateRole",
        "iam:DeleteRole",
        "iam:PutRolePolicy",
        "iam:AttachRolePolicy",
        "iam:DetachRolePolicy",
        "iam:DeleteRolePolicy",
        "iam:GetRolePolicy",
        "iam:PassRole",
        "iam:TagRole",
        "ses:SendEmail",
        "ses:SendRawEmail",
        "logs:*"
      ],
      "Resource": "*"
    }
  ]
}
```

*Note: You can tighten these policies to specific resources once you know your stack names.*

### Step 4: Save Role ARN

After creating the role:
1. Copy the Role ARN (e.g., `arn:aws:iam::123456789012:role/GitHubActionsRole`)
2. In GitHub: Go to your repo → Settings → Secrets and variables → Actions → Secrets
3. Create new secret: `AWS_OIDC_ROLE_ARN` = the role ARN

## Quick Commands (if AWS CLI is available)

```bash
# 1) Create OIDC provider
aws iam create-open-id-connect-provider \
  --url https://token.actions.githubusercontent.com \
  --client-id-list sts.amazonaws.com \
  --thumbprint-list 6938fd4d98bab03faadb97b34396831e3780aea1

# 2) Get your account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
echo "Account ID: $ACCOUNT_ID"

# 3) Create trust policy file (replace YOUR_ACCOUNT_ID)
cat > trust-policy.json <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::$ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:cbgunter/meatfest-catering:*"
        }
      }
    }
  ]
}
EOF

# 4) Create the IAM role
aws iam create-role \
  --role-name GitHubActionsMeatfestRole \
  --assume-role-policy-document file://trust-policy.json

# 5) Attach broad permissions (tighten later)
aws iam attach-role-policy \
  --role-name GitHubActionsMeatfestRole \
  --policy-arn arn:aws:iam::aws:policy/PowerUserAccess

aws iam attach-role-policy \
  --role-name GitHubActionsMeatfestRole \
  --policy-arn arn:aws:iam::aws:policy/IAMFullAccess

# 6) Get role ARN
aws iam get-role --role-name GitHubActionsMeatfestRole --query Role.Arn --output text
```

## After Setup

Once the OIDC provider and role are created:
1. Add the role ARN to GitHub secrets as `AWS_OIDC_ROLE_ARN`
2. Re-run the "Deploy SAM Backend (Forms)" workflow
3. It should now authenticate successfully
