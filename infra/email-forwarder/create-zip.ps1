# Builds email-forwarder.zip from this folder (run `npm install` first).
Add-Type -AssemblyName System.IO.Compression.FileSystem
$dir = $PSScriptRoot
$dest = Join-Path $dir "email-forwarder.zip"
$staging = Join-Path $env:TEMP "email-forwarder-build"
if (Test-Path $dest) { Remove-Item $dest }
if (Test-Path $staging) { Remove-Item $staging -Recurse -Force }
New-Item -ItemType Directory $staging | Out-Null
Copy-Item (Join-Path $dir "email-forwarder.js"), (Join-Path $dir "package.json") $staging
Copy-Item (Join-Path $dir "node_modules") $staging -Recurse
[System.IO.Compression.ZipFile]::CreateFromDirectory($staging, $dest)
Remove-Item $staging -Recurse -Force
Write-Host "Created zip: $dest"
