package com.example.d2pdf_app

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat

class KeepAliveService : Service() {

    companion object {
        const val ACTION_START = "com.example.d2pdf.ACTION_START"
        const val ACTION_UPDATE = "com.example.d2pdf.ACTION_UPDATE"
        const val ACTION_STOP = "com.example.d2pdf.ACTION_STOP"

        const val CHANNEL_ID = "d2pdf_batch_channel"
        const val CHANNEL_NAME = "D2PDF 任务生成与后台保活"
        const val NOTIFICATION_ID = 20261

        @Volatile
        var isRunning: Boolean = false
            private set

        private var wakeLock: PowerManager.WakeLock? = null
        private var wifiLock: WifiManager.WifiLock? = null

        fun start(context: Context, title: String, content: String) {
            isRunning = true
            try {
                if (wakeLock == null) {
                    val pm = context.getSystemService(Context.POWER_SERVICE) as PowerManager
                    wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "D2PDF:KeepAliveWakeLock")
                    wakeLock?.setReferenceCounted(false)
                }
                if (wakeLock?.isHeld != true) {
                    wakeLock?.acquire(3 * 60 * 60 * 1000L) // 3 hours limit
                }

                if (wifiLock == null) {
                    val wm = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as? WifiManager
                    val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        WifiManager.WIFI_MODE_FULL_LOW_LATENCY
                    } else {
                        @Suppress("DEPRECATION")
                        WifiManager.WIFI_MODE_FULL_HIGH_PERF
                    }
                    wifiLock = wm?.createWifiLock(mode, "D2PDF:KeepAliveWifiLock")
                    wifiLock?.setReferenceCounted(false)
                }
                if (wifiLock?.isHeld != true) {
                    wifiLock?.acquire()
                }
            } catch (_: Exception) {}

            val intent = Intent(context, KeepAliveService::class.java).apply {
                action = ACTION_START
                putExtra("title", title)
                putExtra("content", content)
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun update(context: Context, title: String, content: String, progress: Int, max: Int) {
            val intent = Intent(context, KeepAliveService::class.java).apply {
                action = ACTION_UPDATE
                putExtra("title", title)
                putExtra("content", content)
                putExtra("progress", progress)
                putExtra("max", max)
            }
            context.startService(intent)
        }

        fun stop(context: Context) {
            isRunning = false
            try {
                if (wakeLock?.isHeld == true) {
                    wakeLock?.release()
                }
            } catch (_: Exception) {}
            try {
                if (wifiLock?.isHeld == true) {
                    wifiLock?.release()
                }
            } catch (_: Exception) {}

            val intent = Intent(context, KeepAliveService::class.java).apply {
                action = ACTION_STOP
            }
            context.startService(intent)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                isRunning = true
                val title = intent.getStringExtra("title") ?: "HiPDA D2PDF 任务生成"
                val content = intent.getStringExtra("content") ?: "正在后台处理任务，请保持应用运行..."
                createNotificationChannel()
                val notification = buildNotification(title, content, -1, -1)
                try {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        startForeground(NOTIFICATION_ID, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
                    } else {
                        startForeground(NOTIFICATION_ID, notification)
                    }
                } catch (_: Exception) {
                    try {
                        startForeground(NOTIFICATION_ID, notification)
                    } catch (_: Exception) {}
                }
            }
            ACTION_UPDATE -> {
                val title = intent.getStringExtra("title") ?: "HiPDA D2PDF 任务生成"
                val content = intent.getStringExtra("content") ?: "正在导出中..."
                val progress = intent.getIntExtra("progress", -1)
                val max = intent.getIntExtra("max", -1)
                val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                nm.notify(NOTIFICATION_ID, buildNotification(title, content, progress, max))
            }
            ACTION_STOP -> {
                isRunning = false
                try {
                    if (wakeLock?.isHeld == true) {
                        wakeLock?.release()
                    }
                } catch (_: Exception) {}
                try {
                    if (wifiLock?.isHeld == true) {
                        wifiLock?.release()
                    }
                } catch (_: Exception) {}
                stopForeground(true)
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "显示 PDF 批量导出进度及后台保活"
                setShowBadge(false)
            }
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(title: String, content: String, progress: Int, max: Int): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0
        )

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(content)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)

        if (max > 0 && progress >= 0) {
            builder.setProgress(max, progress, false)
        } else {
            builder.setProgress(0, 0, true)
        }

        return builder.build()
    }

    override fun onDestroy() {
        isRunning = false
        try {
            if (wakeLock?.isHeld == true) {
                wakeLock?.release()
            }
        } catch (_: Exception) {}
        try {
            if (wifiLock?.isHeld == true) {
                wifiLock?.release()
            }
        } catch (_: Exception) {}
        super.onDestroy()
    }
}
