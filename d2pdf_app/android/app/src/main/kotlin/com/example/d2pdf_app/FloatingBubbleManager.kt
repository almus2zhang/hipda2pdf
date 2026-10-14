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

    fun show(context: Context, title: String, content: String, progress: Int = -1, max: Int = -1) {
        if (!canDrawOverlays(context)) return

        mainHandler.post {
            try {
                val appContext = context.applicationContext
                val wm = appContext.getSystemService(Context.WINDOW_SERVICE) as WindowManager
                windowManager = wm

                if (isShowing && floatingView != null) {
                    update(title, content, progress, max)
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

                // Sleek capsule container
                val container = LinearLayout(appContext).apply {
                    orientation = LinearLayout.HORIZONTAL
                    setPadding(26, 16, 26, 16)
                    gravity = Gravity.CENTER_VERTICAL
                    elevation = 16f
                    background = android.graphics.drawable.GradientDrawable().apply {
                        setColor(android.graphics.Color.parseColor("#E6192D50")) // D2PDF Navy Blue
                        cornerRadius = 50f
                        setStroke(3, android.graphics.Color.parseColor("#50FFFFFF"))
                    }
                }

                // App icon
                val iconView = ImageView(appContext).apply {
                    setImageResource(R.mipmap.ic_launcher)
                    layoutParams = LinearLayout.LayoutParams(48, 48).apply {
                        marginEnd = 16
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
                        // Max width limit
                        width = 460
                    }
                }

                val titleTv = TextView(appContext).apply {
                    id = 1001
                    val displayTitle = if (max > 0 && progress >= 0) "$title ($progress/$max)" else title
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
                    text = content
                    setTextColor(android.graphics.Color.parseColor("#D0FFFFFF"))
                    textSize = 10f
                    maxLines = 1
                    ellipsize = android.text.TextUtils.TruncateAt.END
                }
                textLayout.addView(contentTv)

                container.addView(textLayout)

                // Touch listener for dragging & click-to-bring-app-to-front
                var initialX = 0
                var initialY = 0
                var initialTouchX = 0f
                var initialTouchY = 0f
                var isDrag = false

                container.setOnTouchListener { _, event ->
                    when (event.action) {
                        MotionEvent.ACTION_DOWN -> {
                            initialX = params.x
                            initialY = params.y
                            initialTouchX = event.rawX
                            initialTouchY = event.rawY
                            isDrag = false
                            true
                        }
                        MotionEvent.ACTION_MOVE -> {
                            val dx = (event.rawX - initialTouchX).toInt()
                            val dy = (event.rawY - initialTouchY).toInt()
                            if (abs(dx) > 12 || abs(dy) > 12) {
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
                            if (!isDrag) {
                                // Bring MainActivity to front
                                val launchIntent = appContext.packageManager.getLaunchIntentForPackage(appContext.packageName)?.apply {
                                    flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT
                                }
                                if (launchIntent != null) {
                                    appContext.startActivity(launchIntent)
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

    fun update(title: String, content: String, progress: Int = -1, max: Int = -1) {
        val view = floatingView ?: return
        mainHandler.post {
            try {
                val titleTv = view.findViewById<TextView>(1001)
                val contentTv = view.findViewById<TextView>(1002)
                val displayTitle = if (max > 0 && progress >= 0) "$title ($progress/$max)" else title
                titleTv?.text = displayTitle
                contentTv?.text = content
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
