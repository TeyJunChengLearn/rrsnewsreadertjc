# Cookie Storage Documentation

## Where Cookies Are Stored on Android

This document explains how cookies are managed and stored in the RSS Reader app, specifically for handling paywalled/subscription content like Malaysiakini.

---

## 1. Native Android Storage

### CookieManager (Primary Storage)

Cookies are stored using Android's native **`CookieManager`** class:

- **Location in code**: `MainActivity.kt:32` - `CookieManager.getInstance()`
- **Physical storage**: Cookies are stored in Android's WebView data directory:
  - **Path**: `/data/data/com.example.flutter_rss_reader_v2/app_webview/Cookies`
  - **Format**: SQLite database managed by the Android WebView system
  - **Persistence**: Cookies persist across app restarts unless explicitly cleared

### Storage Characteristics

- **Automatic management**: Android handles cookie expiration, domain matching, and HTTP-only flags
- **Shared across WebViews**: All WebView instances in the app share the same cookie store
- **Flush required**: Cookies must be flushed to disk using `cookieManager.flush()` to ensure persistence
- **Platform-native**: Cookies are NOT stored in Dart/Flutter code or configuration files

---

## 2. Cookie Architecture Flow

```
User logs in via WebView (SiteLoginPage)
    ↓
WebView captures session cookies automatically
    ↓
Android CookieManager.getInstance() stores them natively
    ↓
cookieManager.flush() writes to disk (/data/data/.../Cookies DB)
    ↓
Dart calls buildHeader(url) via MethodChannel
    ↓
MainActivity.kt retrieves cookies: cookieManager.getCookie(url)
    ↓
Returns Cookie header string to Dart
    ↓
HTTP requests include Cookie header
    ↓
Content extraction happens with authentication
```

---

## 3. Cookie Operations (MainActivity.kt)

### getCookies (Line 25-46)

**Purpose**: Retrieve cookies for a specific URL as a header string

**Implementation**:
```kotlin
val cookieManager = CookieManager.getInstance()
cookieManager.flush()
val cookieString = cookieManager.getCookie(url)
```

**Returns**: `"cookie1=value1; cookie2=value2; ..."`

**Logging**: Outputs cookie count and preview to Android logcat

---

### setCookie (Line 48-63)

**Purpose**: Manually set a cookie for a URL

**Implementation**:
```kotlin
cookieManager.setCookie(url, cookie, ValueCallback<Boolean> { success ->
    cookieManager.flush()
    result.success(success)
})
```

**Usage**: Called by `CookieBridge.injectPaywallCookies()` for fallback/test patterns

---

### clearCookies (Line 65-71)

**Purpose**: Delete all cookies from the CookieManager

**Implementation**:
```kotlin
cookieManager.removeAllCookies(ValueCallback<Boolean> { success ->
    cookieManager.flush()
    result.success(success)
})
```

**Effect**: Clears the entire `/data/data/.../Cookies` database

---

### getAllCookiesForDomain (Line 226-268)

**Purpose**: Get all cookies as a key-value Map for inspection

**Implementation**:
```kotlin
val cookieString = cookieManager.getCookie(url)
cookieString.split(';').forEach { cookie ->
    val parts = cookie.split('=', limit = 2)
    cookieMap[parts[0].trim()] = parts[1].trim()
}
```

**Returns**: `Map<String, String>` of cookie names and values

**Used by**: `CookieBridge.hasSubscriptionCookies()` to detect auth patterns

---

### submitCookies (Line 213-224)

**Purpose**: Flush cookies and return current cookie header

**Implementation**:
```kotlin
cookieManager.flush()
val cookieString = cookieManager.getCookie(url)
result.success(cookieString)
```

**When used**: After WebView login to ensure cookies are persisted

---

## 4. Dart Layer Cookie Bridge

### Location

`lib/services/cookie_bridge.dart` - Dart interface to native cookie operations

### Key Methods

| Method | Purpose | Native Call |
|--------|---------|-------------|
| `buildHeader(url)` | Get Cookie header for HTTP requests | `getCookies` |
| `submitCookies(url)` | Flush and retrieve cookies after login | `submitCookies` |
| `getAllCookiesForDomain(url)` | Get cookies as Map for inspection | `getAllCookiesForDomain` |
| `hasSubscriptionCookies(url)` | Check if auth cookies exist | `getAllCookiesForDomain` + pattern matching |
| `injectPaywallCookies(url)` | Inject test/fallback cookies | `setCookie` |
| `clearCookies()` | Delete all cookies | `clearCookies` |

### MethodChannel Communication

```dart
static const _channel = MethodChannel('com.flutter_rss_reader/cookies');

Future<String?> buildHeader(String url) async {
  return await _channel.invokeMethod<String>('getCookies', {'url': url});
}
```

**Channel**: `com.flutter_rss_reader/cookies` (defined in MainActivity.kt:16)

**Direction**: Dart → MethodChannel → Kotlin → CookieManager → SQLite DB

---

## 5. Cookie Usage in Content Extraction

### Updated Implementation (After Fix)

**File**: `lib/services/readability_service.dart`

**Before** (Line 430-438, BROKEN):
```dart
Map<String, String> _buildRequestHeaders(String url) {
  return {
    'User-Agent': _config.userAgent,
    // NO COOKIES INCLUDED ❌
  };
}
```

**After** (Line 432-451, FIXED):
```dart
Future<Map<String, String>> _buildRequestHeaders(String url) async {
  final headers = {
    'User-Agent': _config.userAgent,
    'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
    // ... other headers
  };

  // Add cookies if builder is available ✅
  if (_cookieHeaderBuilder != null) {
    final cookieHeader = await _cookieHeaderBuilder!(url);
    if (cookieHeader != null && cookieHeader.isNotEmpty) {
      headers['Cookie'] = cookieHeader;
    }
  }

  return headers;
}
```

**Constructor Update** (Line 271):
```dart
final Future<String?> Function(String url)? _cookieHeaderBuilder;

Readability4JExtended({
  // ...
  Future<String?> Function(String url)? cookieHeaderBuilder,
})  : _cookieHeaderBuilder = cookieHeaderBuilder;  // Now stored ✅
```

**Usage**:
```dart
final headers = await _buildRequestHeaders(url);
final response = await _client.get(Uri.parse(url), headers: headers);
```

---

## 6. Malaysiakini-Specific Implementation

### Cookie Patterns

**File**: `lib/services/cookie_bridge.dart:92-102`

```dart
const subscriptionCookieNames = [
  'subscription',
  'premium',
  'member',
  'subscriber',
  'logged_in',
  'session',
  'auth',
  'token',
  'mkini',  // ✅ Malaysiakini-specific pattern added
];
```

### Fallback Injection Patterns

**File**: `lib/services/cookie_bridge.dart:123-129`

```dart
final cookiePatterns = {
  'medium.com': '_uid=1; lightstep_guid/medium=1;',
  'nytimes.com': 'nyt-a=1; nyt-gdpr=0;',
  'bloomberg.com': 'session=test;',
  'wsj.com': 'wsjregion=na;',
  'malaysiakini.com': 'mkini_session=test; subscriber=1;',  // ✅ Added
};
```

**⚠️ WARNING**: These are **placeholder test patterns** only. They will NOT bypass Malaysiakini's paywall. Users must log in properly through the WebView login flow.

### Diagnostic Tool

**File**: `lib/screens/cookie_diagnostic_page.dart`

**Auth Patterns Checked** (Line 84):
```dart
final authPatterns = [
  'mkini',      // Malaysiakini-specific
  'session',
  'auth',
  'subscriber',
  'logged',
  'member',
  'premium',
  'token'
];
```

**Purpose**: Helps users verify their Malaysiakini login status by checking for 'mkini' in cookie names

---

## 7. WebView Rendering with Cookies

### renderPage Method (MainActivity.kt:73-211)

**Cookie Application**:
```kotlin
val cookieManager = CookieManager.getInstance()
applyCookieHeader(url, cookieHeader, cookieManager)
cookieManager.flush()
```

**applyCookieHeader Helper** (Line 275-289):
```kotlin
cookieHeader.split(';').forEach { cookie ->
    cookieManager.setCookie(baseUrl, cookie)  // Set for domain
    cookieManager.setCookie(url, cookie)      // Set for exact URL
}
```

**Verification** (Line 114-119):
```kotlin
val verifyString = cookieManager.getCookie(url)
if (!verifyString.isNullOrEmpty()) {
    Log.d("CookieBridge", "✓ Cookies verified: ...")
} else {
    Log.w("CookieBridge", "⚠ Warning: No cookies found!")
}
```

**Paywall Removal** (Line 141-169):
JavaScript injected after page load to remove overlays, blur effects, and unhide subscriber content.

---

## 8. Data Flow Summary

```
┌─────────────────────────────────────────────────────────────┐
│ 1. User Login                                                │
│    WebView → malaysiakini.com/login                         │
│    User enters credentials                                   │
│    Site sets cookies: Set-Cookie: mkini_session=...         │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 2. Cookie Persistence                                        │
│    Android CookieManager automatically captures cookies      │
│    cookieManager.flush() writes to:                          │
│    /data/data/com.example.flutter_rss_reader_v2/            │
│      app_webview/Cookies (SQLite DB)                         │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 3. Dart Retrieval (via MethodChannel)                       │
│    CookieBridge.buildHeader('malaysiakini.com/article/...')│
│    → MethodChannel → MainActivity.getCookies()               │
│    → CookieManager.getCookie(url)                            │
│    → Returns: "mkini_session=abc123; subscriber=1; ..."     │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 4. HTTP Request with Cookies                                │
│    readability_service._buildRequestHeaders(url)             │
│    → await _cookieHeaderBuilder!(url)  // Calls buildHeader │
│    → headers['Cookie'] = "mkini_session=..."                │
│    → http.get(url, headers: headers)                         │
└─────────────────────────────────────────────────────────────┘
                          ↓
┌─────────────────────────────────────────────────────────────┐
│ 5. Server Response                                           │
│    Malaysiakini server validates cookies                     │
│    Returns full article HTML (not truncated preview)         │
│    Readability service extracts main text                    │
│    Article displayed to user with full content               │
└─────────────────────────────────────────────────────────────┘
```

---

## 9. Cookie Lifespan

| Event | Cookie State | Persistence |
|-------|--------------|-------------|
| User logs in via WebView | Created & stored | Written to DB after flush() |
| App restart | Preserved | Loaded from DB automatically |
| Device reboot | Preserved | DB file persists on filesystem |
| App uninstall | Deleted | App data directory removed |
| User calls clearCookies() | Deleted | DB cleared |
| Cookie expires (server-set expiration) | Auto-deleted | CookieManager handles TTL |

---

## 10. Debugging Cookie Issues

### Android Logcat

Check logcat for cookie operations:

```bash
adb logcat | grep CookieBridge
```

**Example output**:
```
CookieBridge: getCookies(https://www.malaysiakini.com/news/...): Found 3 cookies
CookieBridge:   Cookies: mkini_session=abc123...; subscriber=1; _ga=GA1.2...
CookieBridge: renderPage(https://www.malaysiakini.com/news/...)
CookieBridge:   Applying 3 cookies from header
CookieBridge:   ✓ Cookies verified: mkini_session=abc123...
```

### Cookie Diagnostic Tool

**Access**: Navigate to "Cookie Diagnostic" screen in app

**Tests**:
1. Fetches all cookies for the domain
2. Builds cookie header
3. Checks for auth patterns (including 'mkini')
4. Provides login instructions if no cookies found

**Sample output**:
```
Step 1: Fetching all cookies...
Found 3 cookies
  • mkini_session = abc123def456...
  • subscriber = 1
  • _ga = GA1.2.123456789...

Step 3: Checking for authentication cookies...
✓ Found auth-like cookie patterns: mkini, session
  This suggests you ARE authenticated!

DIAGNOSIS SUMMARY
✓ LOOKS GOOD: You have authentication cookies!
```

---

## 11. Common Issues & Solutions

### Issue: "No cookies found"

**Cause**: User hasn't logged in or cookies expired

**Solution**:
1. Go to "Add feed" → Add Malaysiakini feed
2. Check "Requires login"
3. Log in through the WebView
4. Tap "Save cookies & finish"

---

### Issue: "Preview text only" despite logging in

**Possible causes**:
- Cookies not being included in HTTP requests (FIXED in this update)
- Session expired on server side
- Wrong account (non-subscriber)

**Solution**:
1. Check Cookie Diagnostic tool
2. Verify `hasSubscriptionCookies()` returns true
3. Re-login if needed
4. Check subscription status on Malaysiakini website

---

### Issue: Cookies not persisting after app restart

**Cause**: `flush()` not called after login

**Solution**: Ensure `submitCookies()` is called in `SiteLoginPage` after login (already implemented)

---

## 12. Security Considerations

### Storage Security

- **Encryption**: Cookies stored in plaintext in SQLite DB (Android system default)
- **Permissions**: App data directory is sandboxed (only accessible to app, not other apps)
- **Root access**: Rooted devices can read cookie DB directly

### Best Practices

1. **No hardcoding**: Never hardcode real session cookies in source code ✅
2. **HTTPS only**: Only transmit cookies over HTTPS ✅
3. **User-driven**: Require user login, don't auto-inject credentials ✅
4. **Clear on logout**: Provide clear logout/clear cookies option ✅

---

## 13. File Reference Index

| File | Purpose | Lines |
|------|---------|-------|
| `MainActivity.kt` | Native cookie operations | 16-299 |
| `cookie_bridge.dart` | Dart interface to native cookies | 1-140 |
| `readability_service.dart` | Content extraction with cookies | 266-856 |
| `cookie_diagnostic_page.dart` | Cookie debugging UI | 1-200+ |
| `site_login_page.dart` | WebView login flow | (not shown) |
| `article_webview_page.dart` | WebView with paywall removal | 880-966 |

---

## Summary

**Cookies are stored in**:
- **Primary**: `/data/data/com.example.flutter_rss_reader_v2/app_webview/Cookies` (SQLite)
- **Managed by**: Android `CookieManager` (native platform API)
- **NOT stored in**: JavaScript files, Dart code, or configuration files
- **Accessed via**: MethodChannel bridge between Dart and Kotlin

**Key improvements made**:
1. ✅ Fixed `readability_service.dart` to include cookies in HTTP requests
2. ✅ Added 'mkini' pattern to subscription cookie detection
3. ✅ Added Malaysiakini placeholder to fallback cookie injector (for testing)

**Legitimate access method**:
- User logs in via WebView → Android captures cookies → App uses cookies for authenticated requests
