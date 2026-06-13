package com.example.campus_flow

import android.app.AppOpsManager
import android.app.usage.UsageStatsManager
import android.content.Context
import android.content.Intent
import android.media.AudioManager
import android.os.BatteryManager
import android.os.Build
import android.os.Process
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.Calendar

class MainActivity : FlutterActivity() {

    companion object {
        const val NOTIF_CHANNEL   = "campus_flow/notifications"
        const val USAGE_CHANNEL   = "campus_flow/usage_stats"
        const val CONTEXT_CHANNEL = "campus_flow/activity_context"
        const val BATTERY_CHANNEL = "campus_flow/battery"
    }

    // Sink used by NotificationListenerService to push events to Flutter
    var notificationSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Cache engine so NotificationListenerService can reach it
        FlutterEngineCache.getInstance().put("main_engine", flutterEngine)

        // ── 1. Notification event channel ──────────────────────────────
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIF_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                    notificationSink = sink
                }
                override fun onCancel(args: Any?) {
                    notificationSink = null
                }
            })

        // ── 2. Usage stats method channel ──────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, USAGE_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "hasUsagePermission" -> result.success(hasUsagePermission())
                    "openUsageSettings"  -> {
                        startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                        result.success(null)
                    }
                    "getUsageStats"      -> {
                        val days = call.argument<Int>("days") ?: 7
                        result.success(getUsageStats(days))
                    }
                    else -> result.notImplemented()
                }
            }

        // ── 3. Activity context method channel ─────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CONTEXT_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getActivityContext" -> result.success(getActivityContext())
                    "hasNotifListenerPermission" -> result.success(hasNotifListenerPermission())
                    "openNotifListenerSettings" -> {
                        startActivity(Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        // ── 4. Battery method channel ──────────────────────────────────
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BATTERY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getBatteryLevel" -> result.success(getBatteryLevel())
                    else -> result.notImplemented()
                }
            }
    }

    // ── Helpers ───────────────────────────────────────────────────────────

    private fun hasUsagePermission(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(), packageName
            )
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_GET_USAGE_STATS,
                Process.myUid(), packageName
            )
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    private fun hasNotifListenerPermission(): Boolean {
        val enabledListeners = Settings.Secure.getString(
            contentResolver,
            "enabled_notification_listeners"
        )
        return enabledListeners?.contains(packageName) == true
    }

    private fun getUsageStats(days: Int): List<Map<String, Any>> {
        val usageManager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val cal = Calendar.getInstance()
        val endTime = cal.timeInMillis
        cal.add(Calendar.DAY_OF_YEAR, -days)
        val startTime = cal.timeInMillis

        val stats = usageManager.queryUsageStats(
            UsageStatsManager.INTERVAL_HOURLY,
            startTime, endTime
        )

        return stats
            .filter { it.totalTimeInForeground > 0 }
            .map { stat ->
                val statCal = Calendar.getInstance().apply { timeInMillis = stat.lastTimeUsed }
                mapOf(
                    "app_package"    to stat.packageName,
                    "app_name"       to getAppLabel(stat.packageName),
                    "usage_minutes"  to (stat.totalTimeInForeground / 60000).toInt(),
                    "hour_of_day"    to statCal.get(Calendar.HOUR_OF_DAY),
                    "day_of_week"    to getDayName(statCal.get(Calendar.DAY_OF_WEEK)),
                    "date"           to "${statCal.get(Calendar.YEAR)}-${
                        (statCal.get(Calendar.MONTH)+1).toString().padStart(2,'0')}-${
                        statCal.get(Calendar.DAY_OF_MONTH).toString().padStart(2,'0')}",
                )
            }
    }

    private fun getActivityContext(): Map<String, Any> {
        val audio = getSystemService(Context.AUDIO_SERVICE) as AudioManager
        val headphonesConnected = audio.isWiredHeadsetOn ||
                (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                        audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any {
                            it.type == android.media.AudioDeviceInfo.TYPE_BLUETOOTH_A2DP ||
                            it.type == android.media.AudioDeviceInfo.TYPE_WIRED_HEADPHONES
                        })

        val batteryLevel = getBatteryLevel()

        return mapOf(
            "headphones_connected" to headphonesConnected,
            "battery_level"        to batteryLevel,
            "timestamp"            to System.currentTimeMillis().toString(),
        )
    }

    private fun getBatteryLevel(): Int {
        val bm = getSystemService(Context.BATTERY_SERVICE) as BatteryManager
        return bm.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY)
    }

    private fun getAppLabel(packageName: String): String {
        return try {
            val pm = applicationContext.packageManager
            val info = pm.getApplicationInfo(packageName, 0)
            pm.getApplicationLabel(info).toString()
        } catch (e: Exception) {
            packageName.split(".").last()
        }
    }

    private fun getDayName(dayOfWeek: Int): String = when (dayOfWeek) {
        Calendar.MONDAY    -> "Monday"
        Calendar.TUESDAY   -> "Tuesday"
        Calendar.WEDNESDAY -> "Wednesday"
        Calendar.THURSDAY  -> "Thursday"
        Calendar.FRIDAY    -> "Friday"
        Calendar.SATURDAY  -> "Saturday"
        Calendar.SUNDAY    -> "Sunday"
        else               -> "Monday"
    }
}