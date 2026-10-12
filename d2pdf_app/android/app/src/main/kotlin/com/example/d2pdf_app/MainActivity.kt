package com.example.d2pdf_app

import android.content.Context
import android.os.Build
import android.print.NativePdfPrinter
import android.print.PrintAttributes
import android.print.PrintDocumentAdapter
import android.webkit.CookieManager
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.example.d2pdf/native_printer"

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "printHtmlToPdf" -> {
                    val html = call.argument<String>("html") ?: ""
                    val outputPath = call.argument<String>("outputPath") ?: ""
                    val widthMills = call.argument<Int>("widthMills") ?: 508000
                    val heightMills = call.argument<Int>("heightMills") ?: 720000

                    convertHtmlToPdf(html, outputPath, widthMills, heightMills) { success, err ->
                        if (success) {
                            result.success(outputPath)
                        } else {
                            result.error("PRINT_FAILED", err ?: "PDF generation failed", null)
                        }
                    }
                }
                "flushCookies" -> {
                    CookieManager.getInstance().flush()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun convertHtmlToPdf(
        htmlContent: String,
        outputPath: String,
        widthMills: Int,
        heightMills: Int,
        callback: (Boolean, String?) -> Unit
    ) {
        runOnUiThread {
            try {
                var finished = false
                fun finishOnce(success: Boolean, err: String?) {
                    if (!finished) {
                        finished = true
                        callback(success, err)
                    }
                }

                // 25 second safety timeout to prevent hanging forever
                val handler = android.os.Handler(android.os.Looper.getMainLooper())
                val timeoutRunnable = Runnable {
                    finishOnce(false, "PDF 生成超时，请检查网络或重试")
                }
                handler.postDelayed(timeoutRunnable, 25000)

                val widthPx = (widthMills * 96.0 / 1000.0).toInt().coerceAtLeast(600)
                val heightPx = (heightMills * 96.0 / 1000.0).toInt().coerceAtLeast(1080)

                val webView = WebView(this)
                webView.setBackgroundColor(android.graphics.Color.WHITE)
                val settings = webView.settings
                settings.javaScriptEnabled = true
                settings.domStorageEnabled = true
                settings.useWideViewPort = true
                settings.loadWithOverviewMode = true
                settings.textZoom = 100
                settings.userAgentString = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    CookieManager.getInstance().setAcceptThirdPartyCookies(webView, true)
                }

                // Attach webView to root view hierarchy with invisible visibility so Android WebView does layout & drawing passes
                val rootLayout = window.decorView as? android.view.ViewGroup
                val lp = android.view.ViewGroup.LayoutParams(widthPx, heightPx)
                webView.visibility = android.view.View.INVISIBLE
                rootLayout?.addView(webView, lp)

                fun cleanup() {
                    handler.removeCallbacks(timeoutRunnable)
                    try {
                        rootLayout?.removeView(webView)
                        webView.destroy()
                    } catch (_: Exception) {}
                }

                webView.webViewClient = object : WebViewClient() {
                    override fun onPageFinished(view: WebView?, url: String?) {
                        super.onPageFinished(view, url)
                        // Trigger layout pass with the exact target width
                        view?.measure(
                            android.view.View.MeasureSpec.makeMeasureSpec(widthPx, android.view.View.MeasureSpec.EXACTLY),
                            android.view.View.MeasureSpec.makeMeasureSpec(heightPx, android.view.View.MeasureSpec.EXACTLY)
                        )
                        view?.layout(0, 0, widthPx, heightPx)

                        // Re-measure content height directly in this WebView to guarantee no pagination overflow
                        view?.evaluateJavascript(
                            "Math.max(document.body.scrollHeight || 0, document.documentElement.scrollHeight || 0, document.body.offsetHeight || 0);"
                        ) { measuredHeightStr ->
                            val measured = measuredHeightStr?.replace("\"", "")?.toDoubleOrNull()?.toInt() ?: heightPx
                            val finalHeightPx = Math.max(heightPx, measured + 40)
                            val finalHeightMills = (finalHeightPx * 1000.0 / 96.0).toInt()

                            view?.postDelayed({
                                printWebView(webView, outputPath, widthMills, finalHeightMills) { success, err ->
                                    cleanup()
                                    finishOnce(success, err)
                                }
                            }, 1200)
                        }
                    }
                }

                webView.loadDataWithBaseURL("https://www.4d4y.com/forum/", htmlContent, "text/html", "utf-8", null)
            } catch (e: Exception) {
                callback(false, e.message)
            }
        }
    }

    private fun printWebView(
        webView: WebView,
        outputPath: String,
        widthMills: Int,
        heightMills: Int,
        callback: (Boolean, String?) -> Unit
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.KITKAT) {
            val customMediaSize = PrintAttributes.MediaSize("CUSTOM_MEDIA", "Custom", widthMills, heightMills)
            val attributes = PrintAttributes.Builder()
                .setMediaSize(customMediaSize)
                .setResolution(PrintAttributes.Resolution("PDF_RES", "PDF", 300, 300))
                .setMinMargins(PrintAttributes.Margins.NO_MARGINS)
                .build()

            val adapter: PrintDocumentAdapter = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                webView.createPrintDocumentAdapter("4D4Y_Document")
            } else {
                @Suppress("DEPRECATION")
                webView.createPrintDocumentAdapter()
            }

            val printer = NativePdfPrinter(attributes)
            printer.print(adapter, File(outputPath), object : NativePdfPrinter.Callback {
                override fun onSuccess(filePath: String) {
                    callback(true, null)
                }

                override fun onFailure(error: String?) {
                    callback(false, error)
                }
            })
        } else {
            callback(false, "Android version too low")
        }
    }
}
