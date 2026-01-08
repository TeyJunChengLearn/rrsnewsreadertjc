package com.example.flutter_rss_reader_v2

import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.webkit.CookieManager
import android.webkit.ValueCallback
import android.webkit.WebView
import android.webkit.WebViewClient
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

import io.flutter.embedding.android.FlutterActivity
import org.json.JSONArray
import org.json.JSONObject

private const val CHANNEL = "com.flutter_rss_reader/cookies"

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getCookies" -> {
                        val url = call.argument<String>("url")
                        if (url.isNullOrEmpty()) {
                            result.success(null)
                            return@setMethodCallHandler
                        }

                        val cookieManager = CookieManager.getInstance()
                        cookieManager.flush()
                        val cookieString = cookieManager.getCookie(url)

                        // Log for debugging
                        if (cookieString.isNullOrEmpty()) {
                            android.util.Log.d("CookieBridge", "getCookies($url): No cookies found")
                        } else {
                            val cookieCount = cookieString.split(';').size
                            android.util.Log.d("CookieBridge", "getCookies($url): Found $cookieCount cookies")
                            android.util.Log.d("CookieBridge", "  Cookies: ${cookieString.take(200)}${if (cookieString.length > 200) "..." else ""}")
                        }

                        result.success(cookieString)
                    }

                    "setCookie" -> {
                        val url = call.argument<String>("url")
                        val cookie = call.argument<String>("cookie")

                        if (url.isNullOrEmpty() || cookie.isNullOrEmpty()) {
                            result.success(false)
                            return@setMethodCallHandler
                        }

                        val cookieManager = CookieManager.getInstance()
                        cookieManager.setAcceptCookie(true)
                        cookieManager.setCookie(url, cookie, ValueCallback<Boolean> { success ->
                            cookieManager.flush()
                            result.success(success)
                        })
                    }

                    "clearCookies" -> {
                        val cookieManager = CookieManager.getInstance()
                        cookieManager.removeAllCookies(ValueCallback<Boolean> { success ->
                            cookieManager.flush()
                            result.success(success)
                        })
                    }

                    "renderPage" -> {
                        val url = call.argument<String>("url")
                        val timeoutMs = call.argument<Int>("timeoutMs") ?: 15000
                        val postLoadDelayMs = call.argument<Int>("postLoadDelayMs") ?: 0
                        val userAgent = call.argument<String>("userAgent")
                        val cookieHeader = call.argument<String>("cookieHeader")

                        if (url.isNullOrEmpty()) {
                            result.success(null)
                            return@setMethodCallHandler
                        }

                        val webView = WebView(this)
                        val settings = webView.settings
                        settings.javaScriptEnabled = true
                        settings.domStorageEnabled = true
                        settings.databaseEnabled = true
                        settings.loadsImagesAutomatically = true
                        if (!userAgent.isNullOrEmpty()) {
                            settings.userAgentString = userAgent
                        }

                        val cookieManager = CookieManager.getInstance()
                        cookieManager.setAcceptCookie(true)
                        CookieManager.setAcceptFileSchemeCookies(true)
                        cookieManager.setAcceptThirdPartyCookies(webView, true)

                        // Log cookie info for debugging
                        android.util.Log.d("CookieBridge", "renderPage($url)")
                        if (!cookieHeader.isNullOrBlank()) {
                            val cookieCount = cookieHeader.split(';').size
                            android.util.Log.d("CookieBridge", "  Applying $cookieCount cookies from header")
                            android.util.Log.d("CookieBridge", "  Cookie header: ${cookieHeader.take(200)}${if (cookieHeader.length > 200) "..." else ""}")
                        } else {
                            android.util.Log.d("CookieBridge", "  No cookies to apply (cookieHeader is empty)")
                        }

                        applyCookieHeader(url, cookieHeader, cookieManager)
                        cookieManager.flush()

                        // Verify cookies were set
                        val verifyString = cookieManager.getCookie(url)
                        if (!verifyString.isNullOrEmpty()) {
                            android.util.Log.d("CookieBridge", "  ✓ Cookies verified: ${verifyString.take(200)}${if (verifyString.length > 200) "..." else ""}")
                        } else {
                            android.util.Log.w("CookieBridge", "  ⚠ Warning: No cookies found after applying cookieHeader!")
                        }

                        var completed = false
                        val handler = Handler(Looper.getMainLooper())

                        val timeoutRunnable = Runnable {
                            if (completed) return@Runnable
                            completed = true
                            webView.destroy()
                            result.error("TIMEOUT", "Timed out rendering $url", null)
                        }

                        handler.postDelayed(timeoutRunnable, timeoutMs.toLong())

                        webView.webViewClient = object : WebViewClient() {
                            override fun onPageFinished(view: WebView, finishedUrl: String) {
                                if (completed) return

                                // Use automatic content detection instead of fixed delay
                                // Execute paywall cleanup immediately, then wait for content
                                val paywallRemovalScript = """
                                    (function() {
                                        // Remove common paywall UI elements
                                        document.querySelectorAll('[class*="paywall"], [id*="paywall"], [class*="premium"], [class*="subscribe-modal"], [class*="subscribe-prompt"], .overlay, .modal-backdrop').forEach(el => el.remove());

                                        // Remove blur effects
                                        document.querySelectorAll('*').forEach(el => {
                                            const style = window.getComputedStyle(el);
                                            if (style.filter && (style.filter.includes('blur') || style.webkitFilter && style.webkitFilter.includes('blur'))) {
                                                el.style.filter = 'none';
                                                el.style.webkitFilter = 'none';
                                            }
                                        });

                                        // Unhide elements that might contain subscriber content
                                        document.querySelectorAll('.subscriber-content, .premium-content, .locked-content, [data-subscriber="true"]').forEach(el => {
                                            el.style.display = 'block';
                                            el.style.visibility = 'visible';
                                            el.style.opacity = '1';
                                            el.style.height = 'auto';
                                        });

                                        // Re-enable scrolling (some paywalls disable it)
                                        document.body.style.overflow = 'auto';
                                        document.documentElement.style.overflow = 'auto';

                                        return 'cleanup-done';
                                    })();
                                """.trimIndent()

                                android.util.Log.d("CookieBridge", "  ⏱ Page finished loading, waiting for article content...")

                                // First execute cleanup, then wait for content to load
                                view.evaluateJavascript(paywallRemovalScript) { _ ->
                                    if (completed) return@evaluateJavascript

                                    // Wait for article content to actually appear in the DOM
                                    // This automatically detects when content is ready (no fixed delay)
                                    waitForArticleContent(view, handler, 0) { contentReady ->
                                        if (completed) return@waitForArticleContent

                                        if (contentReady) {
                                            android.util.Log.d("CookieBridge", "  ✓ Article content detected, extracting HTML")
                                        } else {
                                            android.util.Log.w("CookieBridge", "  ⚠ Timeout waiting for content, extracting anyway")
                                        }

                                        view.evaluateJavascript(
                                            "(function(){return document.documentElement.outerHTML;})();"
                                        ) { html ->
                                            if (completed) return@evaluateJavascript
                                            completed = true
                                            handler.removeCallbacks(timeoutRunnable)
                                            cookieManager.flush()
                                            webView.destroy()

                                            android.util.Log.d("CookieBridge", "  ✓ HTML extracted (${decodeJavascriptString(html)?.length ?: 0} chars)")
                                            result.success(decodeJavascriptString(html))
                                        }
                                    }
                                }
                            }

                            override fun onReceivedError(
                                view: WebView,
                                errorCode: Int,
                                description: String?,
                                failingUrl: String?
                            ) {
                                if (completed) return
                                completed = true
                                handler.removeCallbacks(timeoutRunnable)
                                webView.destroy()
                                result.error("LOAD_ERROR", description ?: "WebView load failed", null)
                            }
                        }

                        webView.loadUrl(url)
                    }

                    "submitCookies" -> {
                        val url = call.argument<String>("url")
                        if (url.isNullOrEmpty()) {
                            result.success(null)
                            return@setMethodCallHandler
                        }

                        val cookieManager = CookieManager.getInstance()
                        cookieManager.flush()
                        val cookieString = cookieManager.getCookie(url)
                        result.success(cookieString)
                    }

                    "getAllCookiesForDomain" -> {
                        val url = call.argument<String>("url")
                        if (url.isNullOrEmpty()) {
                            result.success(null)
                            return@setMethodCallHandler
                        }

                        try {
                            val uri = Uri.parse(url)
                            val domain = uri.host ?: ""
                            val cookieManager = CookieManager.getInstance()
                            cookieManager.flush()

                            // Get all cookies for this URL
                            val cookieString = cookieManager.getCookie(url)

                            val cookieMap = mutableMapOf<String, String>()

                            if (!cookieString.isNullOrEmpty()) {
                                // Parse cookie string into key-value pairs
                                cookieString.split(';').forEach { cookie ->
                                    val trimmed = cookie.trim()
                                    val parts = trimmed.split('=', limit = 2)
                                    if (parts.size == 2) {
                                        val key = parts[0].trim()
                                        val value = parts[1].trim()
                                        cookieMap[key] = value
                                    }
                                }
                            }

                            // Log for debugging
                            android.util.Log.d("CookieBridge", "getAllCookiesForDomain($url): Found ${cookieMap.size} cookies")
                            cookieMap.forEach { (k, v) ->
                                android.util.Log.d("CookieBridge", "  Cookie: $k = ${v.take(20)}${if (v.length > 20) "..." else ""}")
                            }

                            result.success(cookieMap)
                        } catch (e: Exception) {
                            android.util.Log.e("CookieBridge", "Error getting cookies: ${e.message}")
                            result.success(emptyMap<String, String>())
                        }
                    }

                    "exportAllCookies" -> {
                        val domains = call.argument<List<String>>("domains")
                        if (domains == null) {
                            result.success(emptyMap<String, Map<String, String>>())
                            return@setMethodCallHandler
                        }

                        try {
                            val cookieManager = CookieManager.getInstance()
                            cookieManager.flush()

                            val allCookies = mutableMapOf<String, Map<String, String>>()

                            android.util.Log.d("CookieBridge", "exportAllCookies: Starting export for ${domains.size} domains")

                            for (domain in domains) {
                                // Try multiple URL variations to get all cookies
                                val baseDomain = domain.removePrefix("www.")
                                val urls = mutableListOf<String>()

                                if (domain.startsWith("http")) {
                                    urls.add(domain)
                                } else {
                                    urls.add("https://$domain")
                                    urls.add("https://www.$baseDomain")
                                    urls.add("http://$domain")
                                    urls.add("http://www.$baseDomain")
                                }

                                val mergedCookies = mutableMapOf<String, String>()

                                for (url in urls) {
                                    val cookieString = cookieManager.getCookie(url)
                                    if (!cookieString.isNullOrEmpty()) {
                                        val cookieMap = parseCookieString(cookieString)
                                        mergedCookies.putAll(cookieMap)  // Merge cookies from all URL variations
                                    }
                                }

                                if (mergedCookies.isNotEmpty()) {
                                    allCookies[domain] = mergedCookies
                                    android.util.Log.d("CookieBridge", "  ✓ $domain: ${mergedCookies.size} cookies")
                                    mergedCookies.forEach { (name, value) ->
                                        android.util.Log.d("CookieBridge", "    - $name = ${value.take(20)}${if (value.length > 20) "..." else ""}")
                                    }
                                } else {
                                    android.util.Log.d("CookieBridge", "  ⚠ $domain: No cookies found")
                                }
                            }

                            android.util.Log.d("CookieBridge", "exportAllCookies: ✓ Exported cookies for ${allCookies.size} of ${domains.size} domains")
                            result.success(allCookies)
                        } catch (e: Exception) {
                            android.util.Log.e("CookieBridge", "Error exporting cookies: ${e.message}")
                            e.printStackTrace()
                            result.success(emptyMap<String, Map<String, String>>())
                        }
                    }

                    "importCookies" -> {
                        val cookies = call.argument<Map<String, Map<String, String>>>("cookies")
                        if (cookies == null) {
                            result.success(false)
                            return@setMethodCallHandler
                        }

                        try {
                            val cookieManager = CookieManager.getInstance()
                            cookieManager.setAcceptCookie(true)

                            var successCount = 0
                            var pendingCallbacks = 0
                            val totalCookies = cookies.values.sumOf { it.size }

                            android.util.Log.d("CookieBridge", "importCookies: Starting import of $totalCookies cookies for ${cookies.size} domains")

                            for ((domain, domainCookies) in cookies) {
                                // Prepare URLs - try both with and without www
                                val baseDomain = domain.removePrefix("www.")
                                val urls = mutableListOf<String>()

                                if (domain.startsWith("http")) {
                                    urls.add(domain)
                                } else {
                                    urls.add("https://$domain")
                                    urls.add("https://www.$baseDomain")
                                    urls.add("http://$domain")
                                    urls.add("http://www.$baseDomain")
                                }

                                android.util.Log.d("CookieBridge", "  Setting cookies for domain: $domain (${domainCookies.size} cookies)")

                                for ((name, value) in domainCookies) {
                                    // Try with domain prefix (standard for cross-subdomain cookies)
                                    val domainWithDot = if (baseDomain.startsWith(".")) baseDomain else ".$baseDomain"

                                    for (url in urls) {
                                        // Set cookie with domain attribute for broader scope
                                        val cookieString = "$name=$value; domain=$domainWithDot; path=/; max-age=31536000"
                                        cookieManager.setCookie(url, cookieString)

                                        // Also set without domain attribute for exact match
                                        val cookieStringExact = "$name=$value; path=/; max-age=31536000"
                                        cookieManager.setCookie(url, cookieStringExact)

                                        successCount++
                                    }

                                    android.util.Log.d("CookieBridge", "    ✓ $name = ${value.take(20)}${if (value.length > 20) "..." else ""}")
                                }
                            }

                            // Flush and wait a bit for cookies to persist
                            cookieManager.flush()
                            Thread.sleep(500) // Give time for cookies to persist

                            android.util.Log.d("CookieBridge", "importCookies: ✓ Successfully imported $successCount cookie entries for ${cookies.size} domains")

                            // Verify cookies were set
                            for ((domain, domainCookies) in cookies) {
                                val url = if (domain.startsWith("http")) domain else "https://$domain"
                                val verifyString = cookieManager.getCookie(url)
                                if (!verifyString.isNullOrEmpty()) {
                                    android.util.Log.d("CookieBridge", "  ✓ Verified $domain: ${verifyString.take(100)}${if (verifyString.length > 100) "..." else ""}")
                                } else {
                                    android.util.Log.w("CookieBridge", "  ⚠ Warning: No cookies found for $domain after import!")
                                }
                            }

                            result.success(true)
                        } catch (e: Exception) {
                            android.util.Log.e("CookieBridge", "Error importing cookies: ${e.message}")
                            e.printStackTrace()
                            result.success(false)
                        }
                    }

                    else -> result.notImplemented()
                }
            }
    }

    /**
     * Waits for article content to appear in the DOM by polling for paragraphs with substantial text.
     * This prevents capturing HTML before JavaScript-loaded content is rendered.
     */
    private fun waitForArticleContent(
        webView: WebView,
        handler: Handler,
        attemptCount: Int,
        callback: (Boolean) -> Unit
    ) {
        val maxAttempts = 10  // Poll up to 10 times
        val pollIntervalMs = 500L  // Check every 500ms

        // JavaScript to check if article content has loaded
        val contentCheckScript = """
            (function() {
                // Look for article containers with common selectors
                const articleSelectors = [
                    'article',
                    '[role="main"]',
                    '.article-body',
                    '.story-body',
                    '.post-content',
                    '.entry-content',
                    '.article-content',
                    'main'
                ];

                let totalTextLength = 0;
                let paragraphCount = 0;

                for (const selector of articleSelectors) {
                    const elements = document.querySelectorAll(selector);
                    for (const element of elements) {
                        const paragraphs = element.querySelectorAll('p');
                        for (const p of paragraphs) {
                            const text = p.textContent.trim();
                            if (text.length > 50) {  // Meaningful paragraph
                                totalTextLength += text.length;
                                paragraphCount++;
                            }
                        }
                    }
                }

                // Consider content loaded if we have at least 3 paragraphs with 500+ total chars
                const hasContent = paragraphCount >= 3 && totalTextLength >= 500;

                return JSON.stringify({
                    hasContent: hasContent,
                    paragraphCount: paragraphCount,
                    totalTextLength: totalTextLength
                });
            })();
        """.trimIndent()

        webView.evaluateJavascript(contentCheckScript) { result ->
            try {
                val jsonStr = decodeJavascriptString(result) ?: "{}"
                val json = org.json.JSONObject(jsonStr)
                val hasContent = json.optBoolean("hasContent", false)
                val paragraphCount = json.optInt("paragraphCount", 0)
                val totalTextLength = json.optInt("totalTextLength", 0)

                android.util.Log.d("CookieBridge", "  Content check attempt ${attemptCount + 1}/$maxAttempts: $paragraphCount paragraphs, $totalTextLength chars")

                if (hasContent) {
                    // Content is ready!
                    callback(true)
                } else if (attemptCount >= maxAttempts - 1) {
                    // Timeout - proceed anyway
                    android.util.Log.w("CookieBridge", "  Content not detected after $maxAttempts attempts, proceeding anyway")
                    callback(false)
                } else {
                    // Try again after delay
                    handler.postDelayed({
                        waitForArticleContent(webView, handler, attemptCount + 1, callback)
                    }, pollIntervalMs)
                }
            } catch (e: Exception) {
                android.util.Log.e("CookieBridge", "  Error checking content: ${e.message}")
                // On error, just proceed
                callback(false)
            }
        }
    }

    private fun applyCookieHeader(
        url: String,
        cookieHeader: String?,
        cookieManager: CookieManager,
    ) {
        if (cookieHeader.isNullOrBlank()) return

        val uri = Uri.parse(url)
        val baseUrl = "${uri.scheme}://${uri.host}"

        cookieHeader.split(';').map { it.trim() }.filter { it.isNotEmpty() }.forEach { cookie ->
            cookieManager.setCookie(baseUrl, cookie)
            cookieManager.setCookie(url, cookie)
        }
    }

    private fun parseCookieString(cookieString: String): Map<String, String> {
        val cookieMap = mutableMapOf<String, String>()
        cookieString.split(';').forEach { cookie ->
            val trimmed = cookie.trim()
            val parts = trimmed.split('=', limit = 2)
            if (parts.size == 2) {
                val key = parts[0].trim()
                val value = parts[1].trim()
                cookieMap[key] = value
            }
        }
        return cookieMap
    }

    private fun decodeJavascriptString(raw: String?): String? {
        if (raw == null) return null
        return try {
            JSONArray("[$raw]").getString(0)
        } catch (e: Exception) {
            raw.trim('"')
        }
    }
}