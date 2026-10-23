package com.daydispatch.app

import android.content.Intent
import android.os.Bundle
import android.util.Log
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var notificationChannel: MethodChannel? = null
    private var pendingDestination: Map<String, String>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        notificationChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NOTIFICATION_CHANNEL,
        ).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "getInitialDestination" -> {
                        val destination = pendingDestination
                        pendingDestination = null
                        result.success(destination)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        destinationFromIntent(intent)?.let { pendingDestination = it }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        configureSystemBars()
    }

    override fun onResume() {
        super.onResume()
        configureSystemBars()
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) configureSystemBars()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        destinationFromIntent(intent)?.let { destination ->
            Log.d(TAG, "Notification tap destination accepted: ${destination["type"]}")
            notificationChannel?.invokeMethod("openNotificationDestination", destination)
                ?: run { pendingDestination = destination }
        }
    }

    private fun destinationFromIntent(intent: Intent?): Map<String, String>? {
        val type = intent?.getStringExtra(EXTRA_TYPE)?.trim().orEmpty()
        val rawUrl = when (type) {
            TYPE_CHAT -> intent?.getStringExtra(EXTRA_CHAT_URL)
            TYPE_ORDER -> intent?.getStringExtra(EXTRA_ORDER_URL)
            else -> null
        }?.trim()

        if (!isSafeRelativePath(rawUrl)) {
            if (type.isNotEmpty() || rawUrl != null) {
                Log.w(TAG, "Notification tap ignored: invalid or missing destination for type=$type")
            }
            return null
        }

        return mapOf("type" to type, "destination_url" to rawUrl!!)
    }

    private fun isSafeRelativePath(value: String?): Boolean {
        if (value.isNullOrBlank() || !value.startsWith("/") || value.startsWith("//")) {
            return false
        }
        if (value.contains('\\') || value.contains('\u0000')) return false
        val uri = runCatching { android.net.Uri.parse(value) }.getOrNull() ?: return false
        return uri.scheme == null && uri.host == null
    }

    private fun configureSystemBars() {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        WindowInsetsControllerCompat(window, window.decorView).apply {
            show(WindowInsetsCompat.Type.systemBars())
            isAppearanceLightStatusBars = true
            isAppearanceLightNavigationBars = true
        }
        window.statusBarColor = android.graphics.Color.WHITE
        window.navigationBarColor = android.graphics.Color.WHITE
    }

    companion object {
        const val NOTIFICATION_CHANNEL = "com.daydispatch.app/notifications"
        const val EXTRA_TYPE = "type"
        const val EXTRA_CHAT_URL = "chat_url"
        const val EXTRA_ORDER_URL = "order_url"
        const val TYPE_CHAT = "chat_notification"
        const val TYPE_ORDER = "order_notification"
        private const val TAG = "DayDispatchFCM"
    }
}
