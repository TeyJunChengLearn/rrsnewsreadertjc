# Debug Build & Logging Guide

## 🔍 How to Get Debug APK with Logs

### Option 1: Run in Debug Mode (Recommended)

```bash
# This automatically builds debug APK and shows logs in terminal
flutter run

# Or specify device
flutter run -d <device-id>
```

**Advantages:**
✅ Automatic log output in terminal
✅ Hot reload enabled
✅ All debug prints visible
✅ Real-time cookie logs

**You'll see logs like:**
```
I/flutter (12345): LocalBackupService: Starting OPML export...
D/CookieBridge(12345): exportAllCookies: Starting export for 5 domains
D/CookieBridge(12345):   ✓ www.malaysiakini.com: 4 cookies
```

### Option 2: Build Debug APK Only

```bash
# Build debug APK (without installing)
flutter build apk --debug

# APK location:
# build/app/outputs/flutter-apk/app-debug.apk
```

**Advantages:**
✅ Can share APK file
✅ Install on multiple devices
✅ No need for Flutter SDK on target device

**To see logs after installing:**
```bash
# Install APK
adb install build/app/outputs/flutter-apk/app-debug.apk

# View logs
adb logcat | grep -E "flutter|CookieBridge"
```

### Option 3: Build Profile APK (Performance Testing)

```bash
# Build profile APK (optimized but still has logs)
flutter build apk --profile

# APK location:
# build/app/outputs/flutter-apk/app-profile.apk
```

---

## 📊 Viewing Cookie Logs

### Method 1: Flutter Run (Easiest)

```bash
flutter run

# Logs appear in terminal automatically:
# - Flutter logs (debugPrint)
# - Android logs (Log.d, Log.w, Log.e)
```

### Method 2: Android Studio Logcat

```
1. Open Android Studio
2. Bottom toolbar → Logcat
3. Filter by: "CookieBridge" or "LocalBackupService"
4. Run your app
5. See logs in real-time
```

### Method 3: ADB Logcat (Command Line)

```bash
# Show all cookie-related logs
adb logcat | grep -E "CookieBridge|LocalBackupService"

# Show only export/import logs
adb logcat | grep -E "exportAllCookies|importCookies"

# Save logs to file
adb logcat | grep -E "CookieBridge" > cookie_logs.txt
```

### Method 4: VS Code (If using VS Code)

```
1. Run: flutter run
2. Debug Console tab (Ctrl+Shift+Y)
3. See all logs in real-time
```

---

## 🧪 Test Cookie Export/Import with Logs

### Step 1: Run in Debug Mode

```bash
cd C:\flutter\codex\rrsnewsreadertjccodex
flutter run
```

### Step 2: Export Backup

```
In app: Settings → Export Backup (OPML)
```

**Expected Logs:**
```
I/flutter (12345): LocalBackupService: Starting OPML export...
I/flutter (12345): LocalBackupService: Exporting cookies for 5 domains
D/CookieBridge(12345): exportAllCookies: Starting export for 5 domains
D/CookieBridge(12345):   ✓ www.malaysiakini.com: 4 cookies
D/CookieBridge(12345):     - mkini_session = abc123...
D/CookieBridge(12345):     - subscriber = 1
D/CookieBridge(12345):     - auth_token = xyz789...
D/CookieBridge(12345):   ✓ www.nytimes.com: 2 cookies
D/CookieBridge(12345):     - nyt-a = token123...
D/CookieBridge(12345):   ⚠ www.bbc.com: No cookies found
D/CookieBridge(12345): exportAllCookies: ✓ Exported cookies for 2 of 5 domains
I/flutter (12345): LocalBackupService: Exported 2 domains with cookies
I/flutter (12345):   www.malaysiakini.com: 4 cookies
I/flutter (12345):   www.nytimes.com: 2 cookies
I/flutter (12345): LocalBackupService: ✓ OPML backup saved to: /storage/...
```

### Step 3: Import Backup

```
In app: Settings → Import Backup (OPML)
```

**Expected Logs:**
```
I/flutter (12345): LocalBackupService: Starting OPML import...
I/flutter (12345): LocalBackupService: Importing cookies...
I/flutter (12345): LocalBackupService: Found cookies for 2 domains
I/flutter (12345):   www.malaysiakini.com: 4 cookies
I/flutter (12345):   www.nytimes.com: 2 cookies
D/CookieBridge(12345): importCookies: Starting import of 6 cookies for 2 domains
D/CookieBridge(12345):   Setting cookies for domain: www.malaysiakini.com (4 cookies)
D/CookieBridge(12345):     ✓ mkini_session = abc123...
D/CookieBridge(12345):     ✓ subscriber = 1
D/CookieBridge(12345):     ✓ auth_token = xyz789...
D/CookieBridge(12345):   ✓ Verified www.malaysiakini.com: mkini_session=abc123; subscriber=1...
D/CookieBridge(12345):   Setting cookies for domain: www.nytimes.com (2 cookies)
D/CookieBridge(12345):     ✓ nyt-a = token123...
D/CookieBridge(12345):   ✓ Verified www.nytimes.com: nyt-a=token123...
D/CookieBridge(12345): importCookies: ✓ Successfully imported 48 cookie entries for 2 domains
I/flutter (12345): LocalBackupService: Cookie import succeeded
```

### Step 4: Open Article

```
In app: Open Malaysiakini article
```

**Expected Logs:**
```
D/CookieBridge(12345): renderPage(https://www.malaysiakini.com/news/12345)
D/CookieBridge(12345):   Applying 4 cookies from header
D/CookieBridge(12345):   Cookie header: mkini_session=abc123; subscriber=1; auth_token=xyz789...
D/CookieBridge(12345):   ✓ Cookies verified: mkini_session=abc123; subscriber=1...
D/CookieBridge(12345):   ✓ HTML extracted (45678 chars)
```

---

## 🚨 Troubleshooting

### Problem: No logs appear

**Solution 1: Check log level**
```bash
# Make sure you're seeing all logs
adb logcat *:V | grep -E "CookieBridge|flutter"
```

**Solution 2: Clear logcat buffer**
```bash
adb logcat -c  # Clear buffer
flutter run    # Run again
```

**Solution 3: Check device connection**
```bash
adb devices
# Should show: device_id    device
```

### Problem: Logs show "⚠ No cookies found"

**This means:**
```
✅ Export/import is working correctly
❌ You haven't logged into that site yet
```

**Solution:**
```
1. Open article from that site
2. Login via WebView
3. Export again
4. Should see "✓ domain: N cookies"
```

### Problem: Import shows success but article still paywalled

**Check logs for:**
```
D/CookieBridge: ✓ Verified www.site.com: session=...

If you see this → Cookies were imported correctly
If you see "⚠ Warning: No cookies found" → Import failed
```

**Solutions:**
```
1. Check if cookies expired
   → Re-login → Export again

2. Check if domain matches
   → www.site.com vs site.com
   → Should both work with new code

3. Check cookie values
   → Compare exported vs imported cookie values
   → Should be identical
```

---

## 📱 Quick Debug Commands

### Start debugging:
```bash
flutter run
```

### Export test:
```
Settings → Export → Check logs for "✓ domain: N cookies"
```

### Import test:
```
Settings → Import → Check logs for "✓ Verified domain: ..."
```

### View all cookie activity:
```bash
adb logcat | grep "CookieBridge"
```

### Save logs to file:
```bash
adb logcat > full_logs.txt
# Perform export/import
# Ctrl+C to stop
# Check full_logs.txt
```

---

## 🎯 What to Look For

### ✅ Good Signs (Export):
```
✓ www.site.com: 4 cookies
  - session = abc123...
  - subscriber = 1
exportAllCookies: ✓ Exported cookies for N domains
```

### ✅ Good Signs (Import):
```
✓ mkini_session = abc123...
✓ Verified www.site.com: session=abc123...
importCookies: ✓ Successfully imported N cookie entries
```

### ✅ Good Signs (Usage):
```
Applying N cookies from header
✓ Cookies verified: session=abc123...
✓ HTML extracted (12345 chars)
```

### ⚠️ Warning Signs (Expected for free sites):
```
⚠ www.bbc.com: No cookies found
(This is normal - BBC is free, no login needed)
```

### ❌ Bad Signs (Need fixing):
```
⚠ Warning: No cookies found for www.site.com after import!
(Import failed - cookies not restored)

No cookies to apply (cookieHeader is empty)
(Cookie bridge not getting cookies)

Error importing cookies: ...
(Import crashed - check error message)
```

---

## 💡 Pro Tips

### Tip 1: Filter logs for specific site
```bash
adb logcat | grep "malaysiakini"
```

### Tip 2: Watch logs in real-time during export
```bash
# Terminal 1:
adb logcat | grep "CookieBridge"

# Terminal 2:
flutter run

# Then perform export in app
```

### Tip 3: Compare export vs import
```bash
# Export
Settings → Export
# Copy logs showing exported cookies

# Import
Settings → Import
# Compare with exported cookies (should match)
```

### Tip 4: Save logs for troubleshooting
```bash
# Start logging
adb logcat > debug_$(date +%Y%m%d_%H%M%S).txt

# Do your testing
# Ctrl+C when done

# Share the .txt file for help
```

---

## ✅ Summary

### To debug cookie export/import:

1. **Run app in debug mode:**
   ```bash
   flutter run
   ```

2. **Watch logs in terminal** (automatic)

3. **Or use Android Studio Logcat** (visual)

4. **Or use adb logcat** (filtered):
   ```bash
   adb logcat | grep "CookieBridge"
   ```

5. **Look for:**
   - ✅ Export: "✓ domain: N cookies"
   - ✅ Import: "✓ Verified domain: ..."
   - ✅ Usage: "✓ Cookies verified: ..."

You don't need `flutter build apk --debug` unless you want to share the APK file. For debugging, just use `flutter run`! 🚀
