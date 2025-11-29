# DNS Migration Checklist

This guide helps you migrate your DNS from your old Google Form site to the new AWS-hosted static site.

## Pre-Migration Checklist

Before changing DNS:
- [ ] CloudFront distribution is deployed and status shows "Deployed"
- [ ] ACM certificate is validated and issued
- [ ] Static site files are uploaded to S3
- [ ] Forms backend (SAM) is deployed
- [ ] Test site loads correctly on CloudFront URL (https://d123abc.cloudfront.net)
- [ ] Test form submission works
- [ ] Verify emails are sending (notification + auto-reply)

## Migration Steps

### Step 1: Get CloudFront Information

```bash
# Get your CloudFront distribution domain name
aws cloudfront list-distributions \
  --query 'DistributionList.Items[?Aliases.Items[?contains(@, `meatfestcatering.com`)]].DomainName' \
  --output text
```

Example output: `d123abc456def.cloudfront.net`

### Step 2: Test Before DNS Switch

Before changing DNS, test that CloudFront is working:

1. Add to your computer's hosts file (`/etc/hosts` on Mac/Linux, `C:\Windows\System32\drivers\etc\hosts` on Windows):
   ```
   # Get CloudFront IP first:
   nslookup d123abc456def.cloudfront.net

   # Then add to hosts file (replace with actual IP):
   12.34.56.78  meatfestcatering.com
   12.34.56.78  www.meatfestcatering.com
   ```

2. Visit `https://meatfestcatering.com` in your browser
3. Test all pages and forms
4. Remove hosts file entries when done testing

### Step 3: Update DNS Records

#### For Route 53:

1. Go to Route 53 → Hosted zones → Your domain
2. **Update A record for root domain:**
   - Name: `@` or leave blank
   - Type: A - IPv4 address
   - Alias: **Yes**
   - Route traffic to: Alias to CloudFront distribution
   - Choose distribution: Select your `d123abc456def.cloudfront.net`
   - Save

3. **Update/Create A record for www:**
   - Name: `www`
   - Type: A - IPv4 address
   - Alias: **Yes**
   - Route traffic to: Alias to CloudFront distribution
   - Choose distribution: Select your `d123abc456def.cloudfront.net`
   - Save

#### For GoDaddy:

1. Log in to GoDaddy → My Products → DNS
2. **For root domain (@):**
   - Type: CNAME (if allowed) or A
   - Name: `@`
   - Value: `d123abc456def.cloudfront.net`
   - TTL: 600 (10 minutes for quick testing, increase to 3600 later)

3. **For www subdomain:**
   - Type: CNAME
   - Name: `www`
   - Value: `d123abc456def.cloudfront.net`
   - TTL: 600

**Note:** GoDaddy may require you to use A records with IPs instead of CNAMEs for root domain. If so:
```bash
# Get CloudFront IPs (they can change, so CNAME/Alias is preferred)
dig d123abc456def.cloudfront.net +short
```

#### For Namecheap:

1. Log in → Domain List → Manage → Advanced DNS
2. **Add/Update CNAME for www:**
   - Type: CNAME Record
   - Host: `www`
   - Value: `d123abc456def.cloudfront.net`
   - TTL: Automatic or 600

3. **For root domain:**
   - Type: ALIAS Record (if available) or URL Redirect
   - Host: `@`
   - Value: `d123abc456def.cloudfront.net` or redirect to `https://www.meatfestcatering.com`

#### For Cloudflare:

1. Log in → Select domain → DNS
2. **Add/Update A record (proxied):**
   - Type: A
   - Name: `@`
   - Content: (Get IP from `dig d123abc456def.cloudfront.net`)
   - Proxy status: Proxied (orange cloud)

3. **Add CNAME for www:**
   - Type: CNAME
   - Name: `www`
   - Content: `d123abc456def.cloudfront.net`
   - Proxy status: Proxied

**Note:** If using Cloudflare proxy, you may want to disable it initially to avoid SSL conflicts.

### Step 4: Lower TTL Before Migration (Optional but Recommended)

If your current DNS records have high TTL (Time To Live), lower them 24-48 hours before migration:

1. Find current A/CNAME records for your domain
2. Change TTL to 300 (5 minutes) or 600 (10 minutes)
3. Wait for old TTL to expire
4. Then proceed with DNS changes

This allows faster rollback if needed.

### Step 5: Verify DNS Propagation

After updating DNS records:

```bash
# Check DNS resolution
dig meatfestcatering.com
dig www.meatfestcatering.com

# Or use nslookup
nslookup meatfestcatering.com
nslookup www.meatfestcatering.com

# Check from multiple locations
# Use online tools:
# - https://www.whatsmydns.net/
# - https://dnschecker.org/
```

DNS propagation can take:
- **5-30 minutes:** For most users
- **1-2 hours:** For global propagation
- **Up to 48 hours:** In rare cases

### Step 6: Test After Migration

Once DNS has propagated:

- [ ] Visit `https://meatfestcatering.com` (should load without SSL warnings)
- [ ] Visit `https://www.meatfestcatering.com` (should work)
- [ ] Test on mobile device
- [ ] Test all pages (Home, Request Catering, Contact)
- [ ] Submit a test form
- [ ] Verify email delivery
- [ ] Check from different networks (home, mobile data, work)
- [ ] Test from different browsers (Chrome, Firefox, Safari, Edge)

### Step 7: Monitor & Increase TTL

After confirming everything works (24-48 hours):

1. Increase TTL back to 3600 (1 hour) or higher
2. Monitor email submissions
3. Check CloudWatch logs for any errors
4. Monitor AWS costs in Billing dashboard

## Rollback Plan (If Needed)

If something goes wrong, you can roll back:

1. **Immediate:** Change DNS records back to old values
2. **Wait:** 5-60 minutes for DNS to propagate back
3. **Verify:** Old site is working again
4. **Debug:** Fix issues with new site
5. **Retry:** When ready

**Keep your old DNS records documented:**
```
# Old DNS records (save these!)
Type    Name    Value                           TTL
A       @       [OLD_IP_ADDRESS]               3600
CNAME   www     [OLD_TARGET]                   3600
```

## Common Issues

### DNS not propagating
- Clear browser cache
- Try incognito/private browsing
- Use `dig` or `nslookup` instead of browser
- Check DNS TTL hasn't expired yet
- Verify DNS provider saved changes

### SSL certificate errors
- Verify ACM certificate includes both domain variations
- Check CloudFront has correct certificate attached
- Ensure alternate domain names (CNAMEs) are configured in CloudFront
- Wait for CloudFront deployment to complete

### Site loads but forms don't work
- Check browser console for errors
- Verify `assets/js/config.js` has correct API URL
- Check CORS settings in API Gateway
- Verify SES emails are verified

### Redirect loops
- Check CloudFront viewer protocol policy is "Redirect HTTP to HTTPS"
- Verify CloudFront is not forwarding Host header incorrectly
- Clear browser cache completely

## Post-Migration Tasks

After successful migration:

- [ ] Update TTL to normal values (3600+)
- [ ] Remove old hosting/Google Form setup (after confirming new site works for 1 week)
- [ ] Set up CloudWatch alarms for errors
- [ ] Configure AWS Budget alerts
- [ ] Update any external links to point to new site
- [ ] Submit new sitemap to Google Search Console
- [ ] Update social media links
- [ ] Test mobile responsiveness thoroughly
- [ ] Set up Google Analytics (if desired)
- [ ] Create backup/snapshot of S3 bucket

## Support Resources

- **CloudFront DNS:** https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/CNAMEs.html
- **Route 53 Alias:** https://docs.aws.amazon.com/Route53/latest/DeveloperGuide/routing-to-cloudfront-distribution.html
- **ACM Validation:** https://docs.aws.amazon.com/acm/latest/userguide/dns-validation.html

## Emergency Contacts

Keep these handy during migration:
- AWS Support: https://console.aws.amazon.com/support/
- Your DNS provider support
- Your domain registrar support
