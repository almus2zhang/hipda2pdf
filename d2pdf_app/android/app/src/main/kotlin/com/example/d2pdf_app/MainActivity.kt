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
                "startKeepAlive" -> {
                    val title = call.argument<String>("title") ?: "HiPDA D2PDF 批量生成"
                    val content = call.argument<String>("content") ?: "正在后台处理任务，请保持应用运行..."
                    val showBubble = call.argument<Boolean>("showBubble") ?: true
                    val isMiniBubble = call.argument<Boolean>("isMiniBubble") ?: false
                    KeepAliveService.start(this, title, content, showBubble, isMiniBubble)
                    result.success(true)
                }
                "updateKeepAlive" -> {
                    val title = call.argument<String>("title") ?: "HiPDA D2PDF 批量生成"
                    val content = call.argument<String>("content") ?: "正在导出中..."
                    val progress = call.argument<Int>("progress") ?: -1
                    val max = call.argument<Int>("max") ?: -1
                    KeepAliveService.update(this, title, content, progress, max)
                    result.success(true)
                }
                "stopKeepAlive" -> {
                    KeepAliveService.stop(this)
                    result.success(true)
                }
                "canDrawOverlays" -> {
                    result.success(FloatingBubbleManager.canDrawOverlays(this))
                }
                "requestOverlayPermission" -> {
                    FloatingBubbleManager.requestOverlayPermission(this)
                    result.success(true)
                }
                "showFloatingBubble" -> {
                    val title = call.argument<String>("title") ?: "HiPDA D2PDF"
                    val content = call.argument<String>("content") ?: "正在处理..."
                    val progress = call.argument<Int>("progress") ?: -1
                    val max = call.argument<Int>("max") ?: -1
                    val isMini = call.argument<Boolean>("isMini") ?: false
                    FloatingBubbleManager.show(this, title, content, progress, max, isMini)
                    result.success(true)
                }
                "updateFloatingBubble" -> {
                    val title = call.argument<String>("title") ?: "HiPDA D2PDF"
                    val content = call.argument<String>("content") ?: "正在处理..."
                    val progress = call.argument<Int>("progress") ?: -1
                    val max = call.argument<Int>("max") ?: -1
                    FloatingBubbleManager.update(title, content, progress, max)
                    result.success(true)
                }
                "setFloatingBubbleMini" -> {
                    val isMini = call.argument<Boolean>("isMini") ?: false
                    FloatingBubbleManager.setMiniMode(this, isMini)
                    result.success(true)
                }
                "hideFloatingBubble" -> {
                    FloatingBubbleManager.hide()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onPause() {
        super.onPause()
        try {
            WebView(applicationContext).resumeTimers()
        } catch (_: Exception) {}
    }

    override fun onStop() {
        super.onStop()
        try {
            WebView(applicationContext).resumeTimers()
        } catch (_: Exception) {}
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

                // 45 second safety timeout to prevent hanging forever
                val handler = android.os.Handler(android.os.Looper.getMainLooper())
                val timeoutRunnable = Runnable {
                    finishOnce(false, "PDF 生成超时，请检查网络或重试")
                }
                handler.postDelayed(timeoutRunnable, 45000)

                val widthPx = (widthMills * 96.0 / 1000.0).toInt().coerceAtLeast(300)
                val heightPx = (heightMills * 96.0 / 1000.0).toInt().coerceAtLeast(300)

                // Use applicationContext so WebView is independent of Activity Window lifecycle
                val webView = WebView(applicationContext)
                webView.onResume()
                webView.resumeTimers()
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

                // Layout directly in memory without attaching to Activity Window/decorView,
                // preventing freeze when Activity is in background or screen is off
                webView.measure(
                    android.view.View.MeasureSpec.makeMeasureSpec(widthPx, android.view.View.MeasureSpec.EXACTLY),
                    android.view.View.MeasureSpec.makeMeasureSpec(heightPx, android.view.View.MeasureSpec.EXACTLY)
                )
                webView.layout(0, 0, widthPx, heightPx)

                fun cleanup() {
                    handler.removeCallbacks(timeoutRunnable)
                    try {
                        webView.stopLoading()
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

                        // Re-measure content height directly in this WebView to eliminate long trailing blank space
                        view?.evaluateJavascript(
                            """(function() {
                                document.documentElement.style.height = 'auto';
                                document.documentElement.style.minHeight = '0';
                                document.body.style.height = 'auto';
                                document.body.style.minHeight = '0';
                                document.body.style.paddingBottom = '0';
                                document.body.style.marginBottom = '0';
                                var wrap = document.getElementById('wrap') || document.querySelector('.wrap');
                                if (wrap) {
                                    wrap.style.height = 'auto';
                                    wrap.style.minHeight = '0';
                                    wrap.style.paddingBottom = '0';
                                    wrap.style.marginBottom = '0';
                                }
                                var postlist = document.getElementById('postlist');
                                var bottomY = 0;
                                if (postlist) {
                                    var rect = postlist.getBoundingClientRect();
                                    var scrollY = window.pageYOffset || document.documentElement.scrollTop || 0;
                                    bottomY = rect.bottom + scrollY;
                                    var tables = postlist.querySelectorAll('table[id^="pid"], table.viewthread, .viewthread');
                                    if (tables.length > 0) {
                                        var last = tables[tables.length - 1];
                                        var r = last.getBoundingClientRect();
                                        var b = r.bottom + scrollY;
                                        if (b > bottomY) bottomY = b;
                                    }
                                }
                                if (bottomY <= 0) {
                                    bottomY = Math.max(document.body.scrollHeight || 0, document.documentElement.scrollHeight || 0);
                                }
                                return Math.ceil(bottomY + 16);
                            })();"""
                        ) { measuredHeightStr ->
                            val measured = measuredHeightStr?.replace("\"", "")?.toDoubleOrNull()?.toInt() ?: heightPx
                            val finalHeightPx = Math.max(measured, heightPx)
                            val finalHeightMills = (finalHeightPx * 1000.0 / 96.0).toInt()

                            // IMPORTANT: Use handler.postDelayed (main looper), NOT view?.postDelayed!
                            // View.postDelayed will halt when Activity is in background!
                            handler.postDelayed({
                                printWebView(webView, outputPath, widthMills, finalHeightMills) { success, err ->
                                    cleanup()
                                    finishOnce(success, err)
                                }
                            }, 1000)
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
