package com.daydispatch.app

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.RingtoneManager
import android.os.Build
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.google.firebase.messaging.RemoteMessage
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService

class DayDispatchFirebaseMessagingService : FlutterFirebaseMessagingService() {
    override fun onNewToken(token: String) {
        super.onNewToken(token)
        getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_TOKEN_REFRESH_PENDING, true)
            .apply()
        // The Flutter Firebase token listener re-registers this token with the
        // authenticated Sanctum session. Never print the token itself.
        Log.i(TAG, "FCM token refreshed; authenticated registration queued")
    }

    override fun onMessageReceived(remoteMessage: RemoteMessage) {
        super.onMessageReceived(remoteMessage)
        val data = remoteMessage.data
        val type = data[MainActivity.EXTRA_TYPE]?.trim().orEmpty()
        Log.d(TAG, "FCM payload received: type=$type, dataKeys=${data.keys.sorted()}")

        val destinationUrl = when (type) {
            MainActivity.TYPE_CHAT -> data[MainActivity.EXTRA_CHAT_URL]
            MainActivity.TYPE_ORDER -> data[MainActivity.EXTRA_ORDER_URL]
            else -> null
        }?.trim()

        if (!isSafeRelativePath(destinationUrl)) {
            Log.w(TAG, "Notification ignored: invalid or missing destination for type=$type")
            return
        }

        val title = remoteMessage.notification?.title
            ?: data["title"]
            ?: "Day Dispatch"
        val body = remoteMessage.notification?.body
            ?: data["body"]
            ?: "You have a new update."
        showNotification(remoteMessage, type, destinationUrl!!, title, body)
    }

    private fun showNotification(
        message: RemoteMessage,
        type: String,
        destinationUrl: String,
        title: String,
        body: String,
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            Log.w(TAG, "Notification not displayed: POST_NOTIFICATIONS permission denied")
            return
        }

        createNotificationChannel()
        val uniqueKey = message.data["notification_id"]
            ?: message.messageId
            ?: "${type}_${System.currentTimeMillis()}"
        val requestCode = uniqueKey.hashCode() and Int.MAX_VALUE
        val tapIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(MainActivity.EXTRA_TYPE, type)
            if (type == MainActivity.TYPE_CHAT) {
                putExtra(MainActivity.EXTRA_CHAT_URL, destinationUrl)
            } else {
                putExtra(MainActivity.EXTRA_ORDER_URL, destinationUrl)
            }
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            requestCode,
            tapIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setSound(RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION))
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setAutoCancel(true)
            .setContentIntent(pendingIntent)
            .build()

        getSystemService(NotificationManager::class.java).notify(requestCode, notification)
        Log.i(TAG, "Native notification created: type=$type, id=$requestCode")
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Day Dispatch Notifications",
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "Chat messages, order updates, and important Day Dispatch alerts."
            enableVibration(true)
            setSound(
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION),
                null,
            )
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun isSafeRelativePath(value: String?): Boolean {
        if (value.isNullOrBlank() || !value.startsWith("/") || value.startsWith("//")) {
            return false
        }
        if (value.contains('\\') || value.contains('\u0000')) return false
        val uri = runCatching { android.net.Uri.parse(value) }.getOrNull() ?: return false
        return uri.scheme == null && uri.host == null
    }

    companion object {
        const val CHANNEL_ID = "daydispatch_notifications"
        private const val TAG = "DayDispatchFCM"
        private const val PREFERENCES = "daydispatch_fcm"
        private const val KEY_TOKEN_REFRESH_PENDING = "token_refresh_pending"
    }
}
