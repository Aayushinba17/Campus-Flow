package com.example.campus_flow

import android.app.Notification
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.MethodChannel

class CampusFlowNotificationListener : NotificationListenerService() {

    companion object {
        const val CHANNEL = "campus_flow/notifications"

        // Apps we care about — extend this list as needed
        val WATCHED_PACKAGES = setOf(
            "com.whatsapp",
            "org.telegram.messenger",
            "com.google.android.gm",            // Gmail
            "com.microsoft.outlook",
            "com.slack",
            "com.android.mms",                  // SMS
            "com.google.android.apps.messaging",
            "com.google.android.classroom",     // Google Classroom (optional)
        )
    }

    override fun onNotificationPosted(sbn: StatusBarNotification?) {
        if (sbn == null) return
        if (sbn.packageName !in WATCHED_PACKAGES) return

        val extras = sbn.notification.extras

        // ✅ FIX: use getCharSequence(), not getString()
        // Many apps (WhatsApp, Gmail, Telegram) store text as SpannableString,
        // which getString() returns null for.
        val title = extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ?: ""
        val text = extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() ?: ""
        val bigText = extras.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString() ?: ""

        // ✅ FIX: Gmail inbox-style puts content in EXTRA_TEXT_LINES (array)
        val textLines = extras.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)
            ?.joinToString("\n") { it.toString() }
            ?: ""

        // Pick the richest body available
        val body = when {
            bigText.isNotBlank() -> bigText
            textLines.isNotBlank() -> textLines
            text.isNotBlank() -> text
            else -> ""
        }

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

        sendToFlutter(data)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification?) {
        // Not needed for now
    }

    private fun sendToFlutter(data: Map<String, String>) {
        try {
            val engine = FlutterEngineCache.getInstance().get("main_engine") ?: return
            val channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            // Method channels must be invoked on the main thread
            android.os.Handler(android.os.Looper.getMainLooper()).post {
                channel.invokeMethod("onNotification", data)
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    private fun getAppName(packageName: String): String {
        return when (packageName) {
            "com.whatsapp"                       -> "WhatsApp"
            "org.telegram.messenger"             -> "Telegram"
            "com.google.android.gm"              -> "Gmail"
            "com.microsoft.outlook"              -> "Outlook"
            "com.slack"                          -> "Slack"
            "com.android.mms"                    -> "SMS"
            "com.google.android.apps.messaging"  -> "Messages"
            "com.google.android.classroom"       -> "Classroom"
            else                                 -> packageName
        }
    }
}