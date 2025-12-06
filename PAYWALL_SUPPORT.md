# Paywall & Subscription Content Support

This RSS Reader supports extracting full content from paywall-protected news sites like Malaysiakini when you have a valid subscription.

## How It Works

The app follows this flow to handle subscription content:

### 1. Add Feed with Login
When adding a new RSS feed (e.g., Malaysiakini):
1. Enter the RSS feed URL
2. App asks: "Does this feed require login?"
3. If you select **Yes**, the app will:
   - Fetch the first article from the feed
   - Open it in a WebView browser
   - Let you log in with your credentials
   - Store your session cookies

### 2. Login Process
- The WebView opens an actual article from the feed
- You log in through the site's normal login page
- After successful login, you can see the full article content
- Tap the **✓ (checkmark)** button to save your login cookies
- The app confirms: "Login successful! Saved N authentication cookies"

### 3. Content Extraction
When fetching article content, the app:
1. Uses stored cookies from your login session
2. Renders the page in WebView with your authentication
3. Automatically removes paywall overlays and unlock prompts
4. Extracts the full subscriber content
5. Returns clean, readable article text

## Supported Features

### Cookie Management
- **Automatic Cookie Sharing**: Login cookies are shared across all WebViews
- **Persistent Storage**: Cookies are saved and reused for future sessions
- **Cookie Detection**: App detects when you have valid authentication cookies

### Paywall Removal
The app automatically removes common paywall elements:
- Subscription prompts and overlays
- Blur effects on content
- "Continue reading" prompts
- Login gates
- Premium content locks

### Hidden Content Extraction
Many paywall sites hide the full article in CSS-hidden elements. The app:
- Detects hidden subscriber content
- Unhides premium article sections
- Removes display restrictions
- Extracts content from JavaScript-rendered elements

## Malaysiakini-Specific Optimizations

The app has special support for Malaysiakini:
- **Site-Specific Selectors**: Knows where Malaysiakini stores article content
- **Cookie Patterns**: Recognizes Malaysiakini authentication cookies
- **Enhanced Rendering**: Gives extra time for authenticated pages to load
- **Mobile User-Agent**: Uses mobile UA for better compatibility

### Malaysiakini Cookie Patterns
The app looks for these cookie names:
- `mkini*` - Malaysiakini session cookies
- `session` - General session cookies
- `auth*` - Authentication tokens
- `subscriber` - Subscription status
- `logged*` - Login state

## Configuration

### Page Load Settings
- **Page Load Delay**: 12 seconds (gives time for JavaScript to render)
- **WebView Timeout**: 25 seconds
- **Max Snapshots**: 4 attempts to get stable content
- **Mobile User-Agent**: Enabled for better mobile site compatibility

### Content Extraction Strategy
The app tries multiple strategies in order:
1. **Authenticated WebView** (highest priority for logged-in users)
2. **Known Subscriber Feeds** (site-specific RSS feeds)
3. **Default Extraction** (desktop user-agent)
4. **Authenticated RSS** (tries subscriber-specific RSS endpoints)
5. **Mobile Strategy** (mobile user-agent)
6. **RSS Fallback** (standard RSS content)

## Usage Tips

### For Malaysiakini Subscribers
1. Add feed: `https://www.malaysiakini.com/rss`
2. Select "Yes" when asked if login is required
3. Log in with your Malaysiakini subscriber account
4. Tap ✓ to save cookies after seeing full article content
5. All future articles will show full subscriber content

### Troubleshooting
- **No full content**: Make sure you clicked ✓ to save cookies after logging in
- **Cookies not working**: Try logging in again from the Feed → Manage tab
- **Partial content**: The site may require re-authentication (session expired)
- **Check logs**: Look for "Login successful!" message after tapping ✓

### Verifying Login Success
After tapping ✓, you should see:
- **Success**: "✓ Login successful! Saved N authentication cookies" (green)
- **Warning**: "⚠️ No cookies detected yet" (need to log in first)
- **Info**: "ℹ️ Saved N cookies (no login cookies detected)" (logged in but no auth cookies found)

## Technical Details

### Architecture
```
1. User adds RSS feed URL (e.g., Malaysiakini)
   ↓
2. RssReader fetches RSS metadata (HttpURLConnection, no cookies)
   - Gets article titles, links, descriptions
   ↓
3. App asks: "Does this feed require login?"
   ↓
4. User selects "Yes" → Login flow starts
   - Fetches first article URL from RSS feed
   - Opens article in WebView
   - User logs in through website
   - WebView stores session cookies
   - User taps ✓ to save cookies
   ↓
5. Cookies stored! Feed added to database
   ↓
6. ReadabilityService extracts article content
   - Uses WebView to load article URLs
   - WebView AUTOMATICALLY sends stored cookies
   - Site recognizes authenticated session
   - Full subscription content returned
   - Paywall elements removed
   - Clean content extracted
```

### Cookie Flow
- **Login WebView** → Stores cookies in Android CookieManager
- **CookieBridge** → Retrieves cookies from CookieManager
- **AndroidWebViewExtractor** → Applies cookies when rendering pages
- **ReadabilityService** → Uses cookies for HTTP requests

### Extraction Layers
1. **JSON-LD Structured Data** (highest quality)
2. **Hidden Subscriber Content** (CSS-hidden premium sections)
3. **Regular Article Extraction** (visible content)
4. **Fallback Text Extraction** (last resort)

## Privacy & Security

- **Local Storage**: Cookies are stored locally on your device
- **No Sharing**: Cookies are never sent to external servers
- **Your Credentials**: Login happens directly with the news site
- **Session Management**: Cookies expire based on the site's policy

## Supported Sites

Optimized for:
- **Malaysiakini** (malaysiakini.com, mkini.bz)
- **New York Times** (nytimes.com)
- **Wall Street Journal** (wsj.com)
- **Financial Times** (ft.com)
- **Bloomberg** (bloomberg.com)
- **Washington Post** (washingtonpost.com)

The app works with any site that uses cookie-based authentication!
