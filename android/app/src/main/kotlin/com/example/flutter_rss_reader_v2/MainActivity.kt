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

                        val cookieString = CookieManager.getInstance().getCookie(url)
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
                        applyCookieHeader(url, cookieHeader, cookieManager)
                        cookieManager.flush()

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

                                    view.evaluateJavascript(
                                        "(function(){return document.documentElement.outerHTML;})();"
                                    ) { html ->
                                        if (completed) return@evaluateJavascript
                                        completed = true
                                        handler.removeCallbacks(timeoutRunnable)
                                        cookieManager.flush()
                                        webView.destroy()
                                        result.success(decodeJavascriptString(html))
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