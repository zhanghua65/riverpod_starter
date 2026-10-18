package com.blz.flutter.riverpod_starter

import android.app.Activity
import android.os.Bundle
import android.widget.ScrollView
import android.widget.TextView

// Shown by Health Connect when the user asks why the app wants sleep data.
// Health Connect refuses to show the permission dialog without it.
class HealthPermissionsActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val padding = (24 * resources.displayMetrics.density).toInt()
        val text = TextView(this).apply {
            setPadding(padding, padding, padding, padding)
            textSize = 16f
            text = "早一点点只读取 Health Connect 里的睡眠记录（例如小米手环同步的数据），" +
                "用来记录你昨晚的实际入睡和醒来时间，代替按熄屏时间推算。\n\n" +
                "数据只在本机读取和保存，不会上传。不写入任何健康数据。\n\n" +
                "可以随时在 Health Connect 里撤销这项权限，撤销后 App 会改回按熄屏时间记录。"
        }
        setContentView(ScrollView(this).apply { addView(text) })
    }
}
