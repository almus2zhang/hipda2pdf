package com.example.d2pdf_app

import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.Gravity
import android.view.MotionEvent
import android.view.View
import android.view.WindowManager
import android.widget.ImageView
import android.widget.LinearLayout
import android.widget.TextView
import kotlin.math.abs

object FloatingBubbleManager {
    private var windowManager: WindowManager? = null
    private var floatingView: View? = null

    @Volatile
    var isShowing: Boolean = false
        private set

    @Volatile
    var isMiniMode: Boolean = false

    private var lastTitle: String = "HiPDA D2PDF"
    private var lastContent: String = "正在生成..."
    private var lastProgress: Int = -1
    private var lastMax: Int = -1

    private val mainHandler = Handler(Looper.getMainLooper())

    fun canDrawOverlays(context: Context): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(context)
        } else {
            true
        }
    }

    fun requestOverlayPermission(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(context)) {
            try {
                val intent = Intent(
                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                    Uri.parse("package:${context.packageName}")
                ).apply {
                    flags = Intent.FLAG_ACTIVITY_NEW_TASK
                }
                context.startActivity(intent)
            } catch (_: Exception) {
                try {
                    val genericIntent = Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION).apply {
                        flags = Intent.FLAG_ACTIVITY_NEW_TASK
                    }
                    context.startActivity(genericIntent)
                } catch (_: Exception) {}
            }
        }
    }

    fun show(
        context: Context,
        title: String,
        content: String,
        progress: Int = -1,
        max: Int = -1,
        isMini: Boolean = false
    ) {
        if (!canDrawOverlays(context)) return

        lastTitle = title
        lastContent = content
        if (progress >= 0) lastProgress = progress
        if (max > 0) lastMax = max
        isMiniMode = isMini

        mainHandler.post {
            try {
                val appContext = context.applicationContext
                val wm = appContext.getSystemService(Context.WINDOW_SERVICE) as WindowManager
                windowManager = wm

                if (isShowing && floatingView != null) {
                    val container = floatingView as? LinearLayout
                    val params = container?.layoutParams as? WindowManager.LayoutParams
                    if (container != null && params != null) {
                        renderBubble(container, params, wm, appContext)
                    }
                    return@post
                }

                val layoutType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                } else {
                    @Suppress("DEPRECATION")
                    WindowManager.LayoutParams.TYPE_PHONE
                }

                val params = WindowManager.LayoutParams(
                    WindowManager.LayoutParams.WRAP_CONTENT,
                    WindowManager.LayoutParams.WRAP_CONTENT,
                    layoutType,
                    WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                            WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
                    PixelFormat.TRANSLUCENT
                ).apply {
                    gravity = Gravity.TOP or Gravity.START
                    x = 30
                    y = 260
                }

                val container = LinearLayout(appContext)
                renderBubble(container, params, wm, appContext)

                // Dragging & click interaction
                var initialX = 0
                var initialY = 0
                var initialTouchX = 0f
                var initialTouchY = 0f
                var isDrag = false
                var downTime = 0L

                val density = appContext.resources.displayMetrics.density
                fun dp(v: Float): Int = (v * density + 0.5f).toInt()

                container.setOnTouchListener { _, event ->
                    when (event.action) {
                        MotionEvent.ACTION_DOWN -> {
                            initialX = params.x
                            initialY = params.y
                            initialTouchX = event.rawX
                            initialTouchY = event.rawY
                            isDrag = false
                            downTime = System.currentTimeMillis()
                            true
                        }
                        MotionEvent.ACTION_MOVE -> {
                            val dx = (event.rawX - initialTouchX).toInt()
                            val dy = (event.rawY - initialTouchY).toInt()
                            if (abs(dx) > dp(5f) || abs(dy) > dp(5f)) {
                                isDrag = true
                            }
                            params.x = initialX + dx
                            params.y = initialY + dy
                            try {
                                wm.updateViewLayout(container, params)
                            } catch (_: Exception) {}
                            true
                        }
                        MotionEvent.ACTION_UP -> {
                            val duration = System.currentTimeMillis() - downTime
                            if (!isDrag) {
                                if (isMiniMode) {
                                    if (duration > 600) {
                                        // Long press on mini dot: expand to capsule
                                        setMiniMode(appContext, false)
                                    } else {
                                        // Tap on mini dot: bring MainActivity to front
                                        bringAppToFront(appContext)
                                    }
                                } else {
                                    // In capsule mode: check if tapped on shrink button area (last 42dp)
                                    if (event.x >= container.width - dp(42f)) {
                                        setMiniMode(appContext, true)
                                    } else {
                                        bringAppToFront(appContext)
                                    }
                                }
                            }
                            true
                        }
                        else -> false
                    }
                }

                wm.addView(container, params)
                floatingView = container
                isShowing = true
            } catch (_: Exception) {}
        }
    }

    private fun bringAppToFront(appContext: Context) {
        val launchIntent = appContext.packageManager.getLaunchIntentForPackage(appContext.packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
        }
        if (launchIntent != null) {
            appContext.startActivity(launchIntent)
        }
    }

    fun setMiniMode(context: Context, mini: Boolean) {
        mainHandler.post {
            isMiniMode = mini
            val view = floatingView as? LinearLayout ?: return@post
            val wm = windowManager ?: return@post
            val params = view.layoutParams as? WindowManager.LayoutParams ?: return@post
            renderBubble(view, params, wm, context.applicationContext)
        }
    }

    private fun renderBubble(
        container: LinearLayout,
        params: WindowManager.LayoutParams,
        wm: WindowManager,
        appContext: Context
    ) {
        container.removeAllViews()
        val density = appContext.resources.displayMetrics.density
        fun dp(v: Float): Int = (v * density + 0.5f).toInt()

        if (isMiniMode) {
            // 迷你圆点按钮：圆形，仅显示 n/n 进度
            val size = dp(52f)
            params.width = size
            params.height = size
            container.orientation = LinearLayout.HORIZONTAL
            container.setPadding(dp(2f), dp(2f), dp(2f), dp(2f))
            container.gravity = Gravity.CENTER
            container.elevation = 16f
            container.background = android.graphics.drawable.GradientDrawable().apply {
                shape = android.graphics.drawable.GradientDrawable.OVAL
                setColor(android.graphics.Color.parseColor("#E6192D50")) // D2PDF Brand Navy Blue
                setStroke(dp(1.8f), android.graphics.Color.parseColor("#80FFFFFF"))
            }

            val displayDot = if (lastMax > 0 && lastProgress >= 0) {
                "$lastProgress/$lastMax"
            } else if (lastProgress >= 0) {
                "$lastProgress"
            } else {
                "0/0"
            }

            val dotTv = TextView(appContext).apply {
                id = 1003
                text = displayDot
                setTextColor(android.graphics.Color.WHITE)
                textSize = if (displayDot.length > 5) 10f else 11.5f
                paint.isFakeBoldText = true
                gravity = Gravity.CENTER
                maxLines = 1
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.MATCH_PARENT,
                    LinearLayout.LayoutParams.MATCH_PARENT
                )
            }
            container.addView(dotTv)

        } else {
            // 经典胶囊样式：图标 + 标题/进度 + 缩小按钮
            params.width = WindowManager.LayoutParams.WRAP_CONTENT
            params.height = WindowManager.LayoutParams.WRAP_CONTENT
            container.orientation = LinearLayout.HORIZONTAL
            container.setPadding(dp(12f), dp(7f), dp(10f), dp(7f))
            container.gravity = Gravity.CENTER_VERTICAL
            container.elevation = 16f
            container.background = android.graphics.drawable.GradientDrawable().apply {
                setColor(android.graphics.Color.parseColor("#E6192D50"))
                cornerRadius = dp(24f).toFloat()
                setStroke(dp(1.2f), android.graphics.Color.parseColor("#50FFFFFF"))
            }

            // App icon
            val iconView = ImageView(appContext).apply {
                setImageResource(R.mipmap.ic_launcher)
                layoutParams = LinearLayout.LayoutParams(dp(24f), dp(24f)).apply {
                    marginEnd = dp(8f)
                }
            }
            container.addView(iconView)

            // Text column
            val textLayout = LinearLayout(appContext).apply {
                orientation = LinearLayout.VERTICAL
                gravity = Gravity.CENTER_VERTICAL
                layoutParams = LinearLayout.LayoutParams(
                    LinearLayout.LayoutParams.WRAP_CONTENT,
                    LinearLayout.LayoutParams.WRAP_CONTENT
                ).apply {
                    width = dp(160f)
                }
            }

            val titleTv = TextView(appContext).apply {
                id = 1001
                val displayTitle = if (lastMax > 0 && lastProgress >= 0) "$lastTitle ($lastProgress/$lastMax)" else lastTitle
                text = displayTitle
                setTextColor(android.graphics.Color.WHITE)
                textSize = 12f
                paint.isFakeBoldText = true
                maxLines = 1
                ellipsize = android.text.TextUtils.TruncateAt.END
            }
            textLayout.addView(titleTv)

            val contentTv = TextView(appContext).apply {
                id = 1002
                text = lastContent
                setTextColor(android.graphics.Color.parseColor("#D0FFFFFF"))
                textSize = 10f
                maxLines = 1
                ellipsize = android.text.TextUtils.TruncateAt.END
            }
            textLayout.addView(contentTv)
            container.addView(textLayout)

            // Shrink button indicator
            val shrinkBtn = TextView(appContext).apply {
                id = 1004
                text = "—"
                setTextColor(android.graphics.Color.parseColor("#A0FFFFFF"))
                textSize = 14f
                paint.isFakeBoldText = true
                gravity = Gravity.CENTER
                setPadding(dp(8f), dp(2f), dp(4f), dp(2f))
            }
            container.addView(shrinkBtn)
        }

        try {
            wm.updateViewLayout(container, params)
        } catch (_: Exception) {}
    }

    fun update(title: String, content: String, progress: Int = -1, max: Int = -1) {
        lastTitle = title
        lastContent = content
        if (progress >= 0) lastProgress = progress
        if (max > 0) lastMax = max

        mainHandler.post {
            val view = floatingView as? LinearLayout ?: return@post
            try {
                if (isMiniMode) {
                    val dotTv = view.findViewById<TextView>(1003)
                    val displayDot = if (lastMax > 0 && lastProgress >= 0) {
                        "$lastProgress/$lastMax"
                    } else if (lastProgress >= 0) {
                        "$lastProgress"
                    } else {
                        "0/0"
                    }
                    dotTv?.text = displayDot
                    dotTv?.textSize = if (displayDot.length > 5) 10f else 11.5f
                } else {
                    val titleTv = view.findViewById<TextView>(1001)
                    val contentTv = view.findViewById<TextView>(1002)
                    val displayTitle = if (lastMax > 0 && lastProgress >= 0) "$lastTitle ($lastProgress/$lastMax)" else lastTitle
                    titleTv?.text = displayTitle
                    contentTv?.text = lastContent
                }
            } catch (_: Exception) {}
        }
    }

    fun hide() {
        mainHandler.post {
            val view = floatingView ?: return@post
            val wm = windowManager ?: return@post
            try {
                wm.removeView(view)
            } catch (_: Exception) {}
            floatingView = null
            isShowing = false
        }
    }
}
