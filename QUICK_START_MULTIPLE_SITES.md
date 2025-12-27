# Quick Start: Using Cookies with Multiple Sites

## 🚀 5-Minute Setup for Multiple Paywalled Sites

### Step 1: Add Your Favorite Paywalled Sites (2 min)

Add RSS feeds for sites you subscribe to:

```
Settings → Manage Feeds → Add Feed

Examples:
✅ Malaysiakini:    https://www.malaysiakini.com/feed
✅ NY Times:        https://rss.nytimes.com/services/xml/rss/nyt/World.xml
✅ Bloomberg:       https://feeds.bloomberg.com/markets/news.rss
✅ Medium:          https://medium.com/feed/@yourusername
✅ WSJ:             https://feeds.a.dj.com/rss/RSSWorldNews.xml
```

### Step 2: Login to Each Site (3 min)

For each paywalled site:

1. **Open any article** from that feed
2. **Tap "Open in WebView"** (or similar button)
3. **Login** using your normal credentials
4. **Close WebView** → ✅ Cookies saved automatically!

**You only do this ONCE per site!**

### Step 3: Export Your Logins (30 sec)

```
Settings → Export Backup (OPML)
Save to: Google Drive
```

✅ **Done!** All your logins are now backed up.

### Step 4: Import on Any Device (30 sec)

```
New device → Install app
Settings → Import Backup (OPML)
Select: Your backup file from Google Drive
```

✅ **Done!** All logins restored. All subscriber content accessible.

---

## 🧪 Quick Test: Verify It Works

### Test 1: Before Export

1. Open Malaysiakini article → ✅ Shows full content (logged in)
2. Export backup → Check logs:
   ```
   ✓ www.malaysiakini.com: 4 cookies
   ```

### Test 2: After Import (New Device)

1. Import backup → Check logs:
   ```
   ✓ Verified www.malaysiakini.com: mkini_session=...
   ```
2. Open Malaysiakini article → ✅ Shows full content (logged in)
3. **No need to login again!**

---

## 📊 Example: Multi-Site Setup

### Real-World Scenario

**Your Subscriptions:**
- 🇲🇾 Malaysiakini (RM 12.90/month)
- 🇺🇸 New York Times ($17/month)
- 📱 Medium ($5/month)
- 💼 Bloomberg ($39.99/month)
- 📰 Wall Street Journal ($38.99/month)

**Total Value:** ~$150/month in subscriptions

### One-Time Setup (5 minutes)

```
1. Add all 5 RSS feeds                    [1 min]
2. Login to all 5 sites via WebView       [3 min]
3. Export backup to Google Drive          [30 sec]
```

### Result

✅ All logins saved in **one 5KB file**
✅ Restore on unlimited devices
✅ Access $150/month worth of content anywhere
✅ Never login again after import

---

## 🎯 Supported Use Cases

### ✅ Personal Use
- Your subscriptions on phone + tablet
- Backup before factory reset
- Migrate to new phone

### ✅ Family Sharing (if allowed by site terms)
- Share family subscription (e.g., NYTimes family plan)
- All family members import same backup
- Everyone gets subscriber access

### ✅ Work Devices
- Company subscriptions (Bloomberg, FT)
- Export from office PC
- Import to personal phone
- Access premium news on-the-go

### ✅ Multi-Device
- Phone (Android)
- Tablet (Android)
- Backup phone
- All synchronized via one backup file

---

## 🔍 Troubleshooting Multiple Sites

### Problem: Site X doesn't show in export logs

**Check:**
```
1. Did you login to site X via WebView?
   → Open article → Login → Close WebView

2. Is the feed URL correct?
   → Check Settings → Manage Feeds

3. Are there articles from site X?
   → Check feed list → Should see articles
```

**Expected Log:**
```
exportAllCookies: Starting export for N domains
  ✓ site-x.com: M cookies    ← Should appear here
```

### Problem: After import, site X shows paywall

**Check:**
```
1. Were cookies exported for site X?
   → Check export logs

2. Were cookies imported successfully?
   → Check import logs for "✓ Verified site-x.com"

3. Did cookies expire?
   → Re-login via WebView → Export again
```

**Expected Log:**
```
importCookies: Starting import
  Setting cookies for domain: site-x.com
    ✓ session = abc123...
  ✓ Verified site-x.com: session=abc123...
```

### Problem: Can't find RSS feed for my site

**Solutions:**
```
1. Check site footer → Usually has RSS icon
2. Google: "site-name RSS feed"
3. Try common patterns:
   - https://site.com/feed
   - https://site.com/rss
   - https://site.com/feed.xml
4. Use RSS discovery tools
```

---

## 📋 Recommended Sites to Add

### News (International)
```
New York Times     - https://rss.nytimes.com/services/xml/rss/nyt/HomePage.xml
Bloomberg          - https://feeds.bloomberg.com/markets/news.rss
Wall Street Journal- https://feeds.a.dj.com/rss/RSSWorldNews.xml
Financial Times    - https://www.ft.com/?format=rss
The Economist      - https://www.economist.com/rss
```

### News (Malaysia/Asia)
```
Malaysiakini       - https://www.malaysiakini.com/feed
The Star           - https://www.thestar.com.my/rss/News
Edge Malaysia      - https://www.theedgemarkets.com/rss/
Straits Times (SG) - https://www.straitstimes.com/rss
SCMP (HK)          - https://www.scmp.com/rss
```

### Tech
```
TechCrunch         - https://techcrunch.com/feed/
Ars Technica       - https://feeds.arstechnica.com/arstechnica/index
Wired              - https://www.wired.com/feed/rss
The Verge          - https://www.theverge.com/rss/index.xml
```

### Business
```
Harvard Business Review - https://hbr.org/feed
Forbes                  - https://www.forbes.com/real-time/feed2/
Business Insider        - https://www.businessinsider.com/rss
```

---

## 💡 Pro Tips

### Tip 1: Batch Login
```
Set aside 5 minutes
Open each site → Login → Close
Do all sites at once
Export once → Never again!
```

### Tip 2: Regular Exports
```
Export backup monthly
Saves latest cookies (in case they refresh)
Store in Google Drive → Auto-sync
Never lose logins
```

### Tip 3: Test Before Clearing
```
Before factory reset:
1. Export backup
2. Import on another device (test)
3. Verify all sites work
4. THEN factory reset
```

### Tip 4: Label Your Backups
```
Instead of: rss_reader_backup_20250127.opml.xml
Use:        rss_reader_5sites_jan2025.opml.xml
            rss_reader_10sites_work.opml.xml
            rss_reader_personal.opml.xml
```

---

## ✅ Summary

### What Works
✅ Unlimited number of sites
✅ Any site with cookie-based login
✅ Multiple simultaneous subscriptions
✅ Restore on unlimited devices
✅ Works across all countries/languages

### What You Need
✅ Valid subscription to each site
✅ Login credentials
✅ 5 minutes for initial setup
✅ Google Drive (for backup storage)

### What You Get
✅ All logins in one file
✅ One-tap restore on new devices
✅ Never login again after import
✅ Access subscriber content everywhere

**Your cookie system is ready for multiple sites!** 🎉

---

## 🎬 Next Steps

1. ✅ Add your favorite paywalled sites
2. ✅ Login to each via WebView
3. ✅ Export backup to Google Drive
4. ✅ Test import on another device
5. ✅ Enjoy subscriber content everywhere!

Questions? Check `SUPPORTED_SITES.md` for full details.
