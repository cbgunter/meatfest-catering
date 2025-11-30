# Meatfest Catering Deployment Script (PowerShell)

Write-Host "🔥 Meatfest Catering - Deployment Script 🔥" -ForegroundColor Yellow
Write-Host ""

# Check AWS CLI
try {
    aws sts get-caller-identity | Out-Null
} catch {
    Write-Host "❌ AWS CLI is not configured or credentials are invalid" -ForegroundColor Red
    Write-Host "Run: aws configure"
    exit 1
}

Write-Host "Finding S3 bucket..." -ForegroundColor Cyan
$buckets = aws s3 ls | Select-String "meatfest"
$bucket = if ($buckets) {
    ($buckets -split '\s+')[2]
} else {
    Read-Host "No meatfest bucket found. Enter S3 bucket name"
}

Write-Host "✓ Using bucket: $bucket" -ForegroundColor Green
Write-Host ""

Write-Host "Finding CloudFront distribution..." -ForegroundColor Cyan
$distId = aws cloudfront list-distributions --query "DistributionList.Items[?contains(Origins.Items[0].DomainName, '$bucket')].Id" --output text

if (-not $distId) {
    $distId = Read-Host "No CloudFront distribution found. Enter Distribution ID (or press Enter to skip)"
}

if ($distId) {
    Write-Host "✓ Using distribution: $distId" -ForegroundColor Green
}
Write-Host ""

# Sync files to S3
Write-Host "Uploading files to S3..." -ForegroundColor Cyan
aws s3 sync . s3://$bucket/ `
    --exclude ".git/*" `
    --exclude "infra/*" `
    --exclude "*.md" `
    --exclude ".gitignore" `
    --exclude "deploy.sh" `
    --exclude "deploy.ps1" `
    --exclude ".github/*" `
    --delete

Write-Host "✓ Files uploaded successfully" -ForegroundColor Green
Write-Host ""

# Invalidate CloudFront cache
if ($distId) {
    Write-Host "Invalidating CloudFront cache..." -ForegroundColor Cyan
    $invalidationId = aws cloudfront create-invalidation `
        --distribution-id $distId `
        --paths "/*" `
        --query 'Invalidation.Id' `
        --output text

    Write-Host "✓ Invalidation created: $invalidationId" -ForegroundColor Green
    Write-Host "Cache will be cleared in a few minutes."
} else {
    Write-Host "⚠️  Skipping CloudFront invalidation (no distribution ID)" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "🎉 Deployment complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Your site should be updated at: https://www.meatfestcatering.com"
Write-Host "Forms are now configured and ready to use!"
