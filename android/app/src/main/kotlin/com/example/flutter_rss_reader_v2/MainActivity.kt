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

                                handler.postDelayed({
                                    if (completed) return@postDelayed

                                    // Execute JavaScript to remove paywall overlays and unhide content
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

                                    // First execute cleanup, then extract HTML
                                    view.evaluateJavascript(paywallRemovalScript) { _ ->
                                        if (completed) return@evaluateJavascript

                                        // Small delay to let DOM settle after manipulations
                                        handler.postDelayed({
                                            if (completed) return@postDelayed

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
                                        }, 500)  // 500ms delay for DOM to settle
                                    }
                                }, postLoadDelayMs.toLong())
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

                    else -> result.notImplemented()
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

    private fun decodeJavascriptString(raw: String?): String? {
        if (raw == null) return null
        return try {
            JSONArray("[$raw]").getString(0)
        } catch (e: Exception) {
            raw.trim('"')
        }
    }
}