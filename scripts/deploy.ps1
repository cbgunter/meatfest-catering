param(
  [Parameter(Mandatory=$true)][string]$BucketName,
  [string]$Region="us-east-1",
  [switch]$InvalidateCloudFront,
  [string]$DistributionId
)

Write-Host "Syncing site to s3://$BucketName (region: $Region)" -ForegroundColor Cyan
aws s3 sync "$PSScriptRoot\.." "s3://$BucketName" --delete --exclude "infra/*" --exclude "scripts/*" --exclude ".git/*" --exclude ".gitignore" --exclude "README.md" --exclude "**/config.example.js" --region $Region

if($LASTEXITCODE -ne 0){ exit $LASTEXITCODE }

if($InvalidateCloudFront -and $DistributionId){
  Write-Host "Creating CloudFront invalidation" -ForegroundColor Cyan
  aws cloudfront create-invalidation --distribution-id $DistributionId --paths "/*"
}

Write-Host "Done." -ForegroundColor Green
