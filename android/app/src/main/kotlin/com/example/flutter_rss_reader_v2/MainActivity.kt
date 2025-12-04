package com.example.flutter_rss_reader_v2

import android.webkit.CookieManager
import android.webkit.ValueCallback
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

import io.flutter.embedding.android.FlutterActivity

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
}