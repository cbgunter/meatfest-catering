# Meatfest Catering – Static Site + AWS Forms

This repo contains a static website (HTML/CSS/JS) and a small AWS Serverless backend (API Gateway + Lambda + DynamoDB + SES) to power the request and contact forms.

- Site pages: `index.html`, `request.html`, `contact.html`
- Assets: `assets/` (CSS, JS, images)
- Backend (forms): `infra/` (AWS SAM template + Lambda code)

## Quick Start

1) Optional: preview locally by opening `index.html` in a browser.
2) Configure and deploy the backend (to enable forms).
3) Create an S3 bucket for static hosting and upload the site.

---

## 1) Backend (Forms) – AWS SAM

This creates an HTTPS endpoint at `/submit` that accepts POSTs from both Request and Contact forms, stores entries in DynamoDB, and emails you via SES.

### Prereqs
- AWS account with credentials configured (`aws configure`).
- Region that supports SES (e.g., `us-east-1`).
- AWS CLI and AWS SAM CLI installed.
- Verify a sender email in SES (Console → Amazon SES → Verified Identities). Note: if SES is in sandbox, also verify the recipient email or request production access.

### Deploy

From `infra/`:

```powershell
# 1) Build
sam build

# 2) Deploy (guided the first time)
sam deploy --guided
```

Recommended answers during `--guided` prompt:
- Stack Name: `meatfest-forms`
- Region: your preferred region (e.g., `us-east-1`)
- Parameter ToEmail: your destination address (where notifications go)
- Parameter FromEmail: the verified SES email identity to send from
- Allow SAM to create roles: `Y`
- Save arguments to `samconfig.toml`: `Y`

After deploy, SAM prints outputs, including `ApiBaseUrl`. Example:

```
ApiBaseUrl = https://abc123.execute-api.us-east-1.amazonaws.com
```

### Connect the Forms

1) Copy the frontend config:

```powershell
Copy-Item .\assets\js\config.example.js .\assets\js\config.js
```

2) Edit `assets/js/config.js` and set:

```js
window.MEATFEST_CONFIG = {
  apiBaseUrl: "https://abc123.execute-api.us-east-1.amazonaws.com"
};
```

3) Try the forms on `request.html` and `contact.html`. You should receive an email and see new items in the DynamoDB table.

### CORS
The backend is configured for CORS `*` by default. If you want to lock it down to your domain, update `infra/template.yaml` → `FormHttpApi.CorsConfiguration.AllowOrigins` and redeploy.

---

## 2) Static Hosting on S3

You can host directly from an S3 static website endpoint or (recommended) front it with CloudFront for HTTPS and better performance. Below are steps for both.

### Option A: S3 Website Endpoint (simple)

1) Create a bucket (must be globally unique):

```powershell
$Bucket = "meatfestcatering-site-<unique>"
aws s3 mb "s3://$Bucket"
```

2) Enable static website hosting and set index/error docs:

```powershell
aws s3 website "s3://$Bucket" --index-document index.html --error-document 404.html
```

3) Make the content publicly readable. Attach a bucket policy (replace the bucket name):

```powershell
$Policy = @'{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "PublicReadGetObject",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::$Bucket/*"
    }
  ]
}'@
aws s3api put-bucket-policy --bucket $Bucket --policy $Policy
```

4) Upload the site:

```powershell
# from repo root
./scripts/deploy.ps1 -BucketName $Bucket -Region us-east-1
```

5) Find the website URL:

```powershell
aws s3api get-bucket-website --bucket $Bucket
# Or: http://$Bucket.s3-website-<region>.amazonaws.com
```

Note: S3 website endpoints are HTTP-only. For HTTPS and custom domains, use CloudFront.

### Option B: CloudFront (recommended)

- Create/choose a public S3 bucket to store the site (no public policy needed when using OAC).
- Create a CloudFront distribution:
  - Origin: your S3 bucket (use Origin Access Control/OAC).
  - Default Root Object: `index.html`.
  - Cache Policy: CachingOptimized (default is fine).
  - Alternate domain (CNAME): `www.meatfestcatering.com` (optional).
  - TLS certificate: Create/validate in ACM (in `us-east-1` for CloudFront).
- Point DNS (Route 53 or your registrar) `CNAME` to the CloudFront domain.
- Deploy site files:

```powershell
./scripts/deploy.ps1 -BucketName $Bucket -Region us-east-1 -InvalidateCloudFront -DistributionId E123EXAMPLE
```

---

## Content & Settings

- Update text content in the HTML files directly.
- Replace the placeholder logo (`assets/img/logo.svg`) and favicon if desired.
- Tweak styles in `assets/css/styles.css`.

---

## Troubleshooting

- Forms not sending: ensure `assets/js/config.js` exists and `apiBaseUrl` matches the SAM output; verify SES identities (sender and, if in sandbox, recipient).
- 403 on S3 website: ensure the bucket policy allows public `s3:GetObject` and that the object ACLs are not `private` if ACLs are enabled. If using CloudFront + OAC, do not set public bucket policy—use the CloudFront-managed policy.
- CORS errors: set the exact site origin in `template.yaml` CORS if you tightened it.

---

## Clean Up

- Remove CloudFront distribution, then S3 bucket (after emptying), then the SAM stack:

```powershell
sam delete --stack-name meatfest-forms
```

---

## CI/CD with GitHub Actions (Deploy from Repo)

This repo includes two workflows under `.github/workflows/`:
- `deploy-site.yml`: syncs the static site to your S3 bucket and optionally invalidates CloudFront.
- `deploy-infra.yml`: builds and deploys the SAM backend for forms.

### 1) Configure AWS OIDC for GitHub
Create an IAM role in your AWS account that trusts GitHub’s OIDC provider and allows needed actions (S3, CloudFront invalidation, CloudFormation, Lambda, API Gateway, DynamoDB, SES for the SAM stack).

Minimal trust policy (replace OWNER and REPO):

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {"Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com"},
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:OWNER/REPO:*"
        }
      }
    }
  ]
}
```

Attach policies:
- For site deploy: `s3:PutObject`, `s3:DeleteObject`, `s3:ListBucket`, and optionally `cloudfront:CreateInvalidation`.
- For infra deploy: permissions for `cloudformation`, `iam:PassRole`, `lambda`, `apigateway`, `dynamodb`, `ses:SendEmail` (SAM will create least-privilege resources based on `template.yaml`).

Save the role ARN as a repo secret `AWS_OIDC_ROLE_ARN`.

### 2) Set Repo Variables and Secrets
Repository → Settings → Secrets and variables → Actions:
- Variables:
  - `AWS_REGION`: e.g., `us-east-1`
  - `S3_BUCKET`: your static site bucket name
  - `DISTRIBUTION_ID`: (optional) CloudFront distribution ID
  - `SAM_STACK_NAME`: (optional) defaults to `meatfest-forms`
- Secrets:
  - `AWS_OIDC_ROLE_ARN`: IAM role ARN from step 1
  - `TO_EMAIL`: destination email for form notifications
  - `FROM_EMAIL`: SES-verified sender email

### 3) Use the Workflows
- Push to `main` that changes site files triggers `deploy-site.yml`.
- Push to `main` that changes `infra/**` triggers `deploy-infra.yml`.
- You can also trigger either workflow manually from the Actions tab.

After deploying the backend, set the frontend API URL:

```powershell
Copy-Item .\assets\js\config.example.js .\assets\js\config.js
notepad .\assets\js\config.js
```

Update `apiBaseUrl` to the `ApiBaseUrl` output from the SAM stack.
