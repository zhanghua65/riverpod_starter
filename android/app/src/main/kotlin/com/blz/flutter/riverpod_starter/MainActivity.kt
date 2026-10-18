package com.blz.flutter.riverpod_starter

import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
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

    // Vendor settings pages are undocumented and move between ROM versions:
    // returns false when the page is missing so the caller can fall back to
    // the generic app settings.
    private fun openFirst(intent: Intent): Boolean = try {
        startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
        true
    } catch (e: Exception) {
        false
    }

    companion object {
        private const val CHANNEL = "rhythm_compass/permissions"
    }
}
