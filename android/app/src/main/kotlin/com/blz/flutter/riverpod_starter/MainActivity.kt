package com.blz.flutter.riverpod_starter

import android.app.AppOpsManager
import android.app.NotificationManager
import android.app.usage.UsageEvents
import android.app.usage.UsageStatsManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val background = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canUseFullScreenIntent" -> result.success(canUseFullScreenIntent())
                    "openFullScreenIntentSettings" -> {
                        openFullScreenIntentSettings()
                        result.success(null)
                    }
                    "manufacturer" -> result.success(Build.MANUFACTURER.lowercase())
                    "openAutoStartSettings" -> result.success(
                        openFirst(
                            Intent().setComponent(
                                ComponentName(
                                    "com.miui.securitycenter",
                                    "com.miui.permcenter.autostart.AutoStartManagementActivity",
                                ),
                            ),
                        ),
                    )
                    "openBatteryStrategySettings" -> result.success(
                        openFirst(
                            Intent()
                                .setClassName(
                                    "com.miui.powerkeeper",
                                    "com.miui.powerkeeper.ui.HiddenAppsConfigActivity",
                                )
                                .putExtra("package_name", packageName)
                                .putExtra("package_label", applicationInfo.loadLabel(packageManager).toString()),
                        ),
                    )
                    "openPermissionEditor" -> result.success(
                        openFirst(
                            Intent("miui.intent.action.APP_PERM_EDITOR")
                                .setClassName(
                                    "com.miui.securitycenter",
                                    "com.miui.permcenter.permissions.PermissionsEditorActivity",
                                )
                                .putExtra("extra_pkgname", packageName),
                        ),
                    )
                    // App-specific external dir: no permission needed, and
                    // `adb pull` can read it.
                    "logDir" -> result.success(getExternalFilesDir(null)?.absolutePath)
                    "buildInfo" -> result.success(buildInfo())
                    "hasUsageAccess" -> result.success(hasUsageAccess())
                    "openUsageAccessSettings" -> {
                        openUsageAccessSettings()
                        result.success(null)
                    }
                    "screenEvents" -> {
                        val from = (call.argument<Number>("from") ?: 0).toLong()
                        val to = (call.argument<Number>("to") ?: 0).toLong()
                        // Walking a night of usage events is slow; keep it
                        // off the UI thread and reply on the main looper.
                        background.execute {
                            val events = try {
                                screenEvents(from, to)
                            } catch (e: Exception) {
                                null
                            }
                            mainHandler.post { result.success(events) }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // Version, commit and install time of this build, for the diagnostic log.
    private fun buildInfo(): String {
        val info = packageManager.getPackageInfo(packageName, 0)
        val installed = SimpleDateFormat("MM-dd HH:mm", Locale.US).format(Date(info.lastUpdateTime))
        return "${info.versionName} ${BuildConfig.GIT_COMMIT} installed $installed"
    }

    // Android 14+ can withhold the full-screen intent that lights the screen
    // for the alarm page; before that it is always granted.
    private fun canUseFullScreenIntent(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return true
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        return manager.canUseFullScreenIntent()
    }

    private fun openFullScreenIntentSettings() {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            Intent(Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT, Uri.parse("package:$packageName"))
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
        }
        startActivity(intent)
    }

    // Usage access is a special app-op the user grants in the system
    // settings; it lets the app read when the screen turned on and off.
    private fun hasUsageAccess(): Boolean {
        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            appOps.unsafeCheckOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName)
        } else {
            @Suppress("DEPRECATION")
            appOps.checkOpNoThrow(AppOpsManager.OPSTR_GET_USAGE_STATS, Process.myUid(), packageName)
        }
        return mode == AppOpsManager.MODE_ALLOWED
    }

    // Some ROMs ignore the package uri and some reject it, so fall back to
    // the plain list and then to the app's details page.
    private fun openUsageAccessSettings() {
        openFirst(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS, Uri.parse("package:$packageName"))) ||
            openFirst(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS)) ||
            openFirst(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
    }

    // Screen on/off events between [from] and [to] (epoch millis). Null when
    // the system does not record them (before Android 9) or access is denied.
    private fun screenEvents(from: Long, to: Long): List<Map<String, Any>>? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P || !hasUsageAccess()) return null
        val manager = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val events = manager.queryEvents(from, to) ?: return null
        val result = mutableListOf<Map<String, Any>>()
        val event = UsageEvents.Event()
        while (events.hasNextEvent()) {
            events.getNextEvent(event)
            when (event.eventType) {
                UsageEvents.Event.SCREEN_INTERACTIVE ->
                    result.add(mapOf("at" to event.timeStamp, "on" to true))
                UsageEvents.Event.SCREEN_NON_INTERACTIVE ->
                    result.add(mapOf("at" to event.timeStamp, "on" to false))
            }
        }
        return result
    }

    // Vendor settings pages are undocumented and move between ROM versions:
    // returns false when the page is missing so the caller can fall back to
    // the generic app settings.
    private fun openFirst(intent: Intent): Boolean = try {
        startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (e: Exception) {
        false
    }

    override fun onDestroy() {
        background.shutdown()
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "rhythm_compass/permissions"
    }
}
