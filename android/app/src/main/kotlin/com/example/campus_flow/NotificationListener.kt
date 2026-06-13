package com.example.campus_flow

import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class CampusFlowNotificationListener : NotificationListenerService() {

    companion object {
        const val CHANNEL = "campus_flow/notifications"
        // Apps we care about — extend this list as needed
        val WATCHED_PACKAGES = setOf(
            "com.whatsapp",
            "org.telegram.messenger",
            "com.google.android.gm",          // Gmail
            "com.microsoft.outlook",
            "com.slack",
            "com.android.mms",                 // SMS
            "com.google.android.apps.messaging",
        )
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        sbn ?: return
        if (sbn.packageName !in WATCHED_PACKAGES) return

        val extras: Bundle = sbn.notification.extras ?: return
        val title = extras.getCharSequence("android.title")?.toString() ?: return
        val body  = extras.getCharSequence("android.text")?.toString()  ?: return

        // Skip empty or system notifications
        if (title.isBlank() || body.isBlank()) return

        val data = mapOf(
            "app_package"     to sbn.packageName,
            "app_name"        to getAppName(sbn.packageName),
            "title"           to title,
            "body"            to body,
            "timestamp"       to sbn.postTime.toString(),
            "notification_id" to sbn.id.toString(),
        )

        // Send to Flutter via method channel
        sendToFlutter(data)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        // Not needed for now
    }

    private fun sendToFlutter(data: Map<String, String>) {
        try {
            val engine = FlutterEngineCache.getInstance().get("main_engine") ?: return
            val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            // Run on main thread
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                channel.invokeMethod("onNotification", data)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun getAppName(packageName: String): String {
        return when (packageName) {
            "com.whatsapp"                      -> "WhatsApp"
            "org.telegram.messenger"            -> "Telegram"
            "com.google.android.gm"             -> "Gmail"
            "com.microsoft.outlook"             -> "Outlook"
            "com.slack"                         -> "Slack"
            "com.android.mms"                   -> "SMS"
            "com.google.android.apps.messaging" -> "Messages"
            else                                -> packageName
        }
    }
}