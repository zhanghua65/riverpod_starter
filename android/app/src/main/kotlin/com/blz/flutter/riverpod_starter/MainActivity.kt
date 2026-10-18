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
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.time.Instant
import java.util.concurrent.Executors
import kotlinx.coroutines.MainScope
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

class MainActivity : FlutterActivity() {
    private val background = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private val scope = MainScope()

    // The Dart call waiting for Health Connect's permission dialog.
    private var pendingHealthResult: MethodChannel.Result? = null

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
                    "healthStatus" -> scope.launch { result.success(healthStatus()) }
                    "requestHealthAccess" -> requestHealthAccess(result)
                    "openHealthConnect" -> {
                        openFirst(Intent(HealthConnectClient.ACTION_HEALTH_CONNECT_SETTINGS)) ||
                            openFirst(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
                        result.success(null)
                    }
                    "openBandApp" -> result.success(
                        BAND_APPS.any { pkg ->
                            packageManager.getLaunchIntentForPackage(pkg)?.let { openFirst(it) } ?: false
                        },
                    )
                    "sleepSessions" -> {
                        val from = (call.argument<Number>("from") ?: 0).toLong()
                        val to = (call.argument<Number>("to") ?: 0).toLong()
                        scope.launch {
                            val sessions = try {
                                sleepSessions(from, to)
                            } catch (e: Exception) {
                                // No permission (SecurityException) or Health
                                // Connect not reachable.
                                null
                            }
                            result.success(sessions)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
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

    private fun healthConnectAvailable(): Boolean =
        HealthConnectClient.getSdkStatus(this) == HealthConnectClient.SDK_AVAILABLE

    // "unavailable", "needsUpdate", "denied" or "granted"; matches the Dart
    // HealthSleepStatus names.
    private suspend fun healthStatus(): String = when (HealthConnectClient.getSdkStatus(this)) {
        HealthConnectClient.SDK_AVAILABLE -> if (hasSleepAccess()) "granted" else "denied"
        HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED -> "needsUpdate"
        else -> "unavailable"
    }

    private suspend fun hasSleepAccess(): Boolean = try {
        HealthConnectClient.getOrCreate(this)
            .permissionController
            .getGrantedPermissions()
            .contains(SLEEP_PERMISSION)
    } catch (e: Exception) {
        false
    }

    // Shows Health Connect's permission dialog and replies once it closes,
    // in onActivityResult. When Health Connect is outdated, opens its store
    // page instead and replies false.
    private fun requestHealthAccess(result: MethodChannel.Result) {
        when (HealthConnectClient.getSdkStatus(this)) {
            HealthConnectClient.SDK_AVAILABLE -> {
                pendingHealthResult?.success(false)
                pendingHealthResult = result
                try {
                    val intent = PermissionController.createRequestPermissionResultContract()
                        .createIntent(this, setOf(SLEEP_PERMISSION))
                    startActivityForResult(intent, HEALTH_REQUEST)
                } catch (e: Exception) {
                    pendingHealthResult = null
                    result.success(false)
                }
            }
            HealthConnectClient.SDK_UNAVAILABLE_PROVIDER_UPDATE_REQUIRED -> {
                openFirst(
                    Intent(Intent.ACTION_VIEW, Uri.parse("market://details?id=$HEALTH_CONNECT_PACKAGE")),
                )
                result.success(false)
            }
            else -> result.success(false)
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == HEALTH_REQUEST) {
            val granted = PermissionController.createRequestPermissionResultContract()
                .parseResult(resultCode, data)
            pendingHealthResult?.success(granted.contains(SLEEP_PERMISSION))
            pendingHealthResult = null
            return
        }
        super.onActivityResult(requestCode, resultCode, data)
    }

    // Sleep sessions between [from] and [to] (epoch millis), from every app
    // that writes them. Null when Health Connect is missing.
    private suspend fun sleepSessions(from: Long, to: Long): List<Map<String, Any>>? {
        if (!healthConnectAvailable() || !hasSleepAccess()) return null
        val response = HealthConnectClient.getOrCreate(this).readRecords(
            ReadRecordsRequest(
                recordType = SleepSessionRecord::class,
                timeRangeFilter = TimeRangeFilter.between(
                    Instant.ofEpochMilli(from),
                    Instant.ofEpochMilli(to),
                ),
            ),
        )
        return response.records.map {
            mapOf(
                "start" to it.startTime.toEpochMilli(),
                "end" to it.endTime.toEpochMilli(),
                "source" to it.metadata.dataOrigin.packageName,
            )
        }
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
        scope.cancel()
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "rhythm_compass/permissions"
        private const val HEALTH_REQUEST = 4201
        private const val HEALTH_CONNECT_PACKAGE = "com.google.android.apps.healthdata"
        private val SLEEP_PERMISSION = HealthPermission.getReadPermission(SleepSessionRecord::class)

        // 小米运动健康 (China) and Mi Fitness (global); they sync the band's
        // sleep to Health Connect.
        private val BAND_APPS = listOf("com.mi.health", "com.xiaomi.wearable")
    }
}
