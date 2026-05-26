package com.uniyi.uni_yi.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.widget.RemoteViews
import com.uniyi.uni_yi.R
import es.antonborri.home_widget.HomeWidgetPlugin

/**
 * 桌面小组件：下节课。
 *
 * - 数据源：HomeWidget 插件统一写入到 [HomeWidgetPlugin.getData] 这块共享 prefs，
 *   key 与 Dart 那边的 HomeWidgetService 完全对齐。
 * - 点击：跳回 App 主页（schedule branch），通过 `home_widget://` deeplink 处理。
 *   这里直接用 launch intent，简单稳。
 */
class NextClassWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val prefs: SharedPreferences = HomeWidgetPlugin.getData(context)
        val hasNext = prefs.getBoolean("next_class.has", false)
        val courseName = prefs.getString("next_class.courseName", "暂无课程信息") ?: "暂无课程信息"
        val subtitle = prefs.getString("next_class.subtitle", "") ?: ""
        val timeRange = prefs.getString("next_class.timeRange", "") ?: ""
        val location = prefs.getString("next_class.location", "") ?: ""
        val teacher = prefs.getString("next_class.teacher", "") ?: ""

        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.next_class_widget)
            views.setTextViewText(R.id.widget_subtitle, subtitle)
            views.setTextViewText(R.id.widget_course, courseName)
            views.setTextViewText(R.id.widget_time, timeRange)
            views.setTextViewText(
                R.id.widget_meta,
                listOfNotNull(
                    location.takeIf { it.isNotBlank() },
                    teacher.takeIf { it.isNotBlank() },
                ).joinToString(" · "),
            )
            // 不可见时间/位置文本时收起，避免空字符串挤位。
            views.setViewVisibility(
                R.id.widget_time,
                if (hasNext && timeRange.isNotBlank()) android.view.View.VISIBLE else android.view.View.GONE,
            )
            views.setViewVisibility(
                R.id.widget_meta,
                if (hasNext && (location.isNotBlank() || teacher.isNotBlank()))
                    android.view.View.VISIBLE
                else android.view.View.GONE,
            )

            // 点击跳回 App。
            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (launchIntent != null) {
                launchIntent.data = Uri.parse("uniyi://widget/next-class")
                val pi = PendingIntent.getActivity(
                    context,
                    0,
                    launchIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
                views.setOnClickPendingIntent(R.id.widget_root, pi)
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    /**
     * Dart 那边调用 home_widget.updateWidget 时会触发这个，
     * 我们把所有现存的小组件实例 ID 拉出来再走一遍 onUpdate。
     */
    override fun onReceive(context: Context, intent: Intent) {
        super.onReceive(context, intent)
        if (intent.action == AppWidgetManager.ACTION_APPWIDGET_UPDATE) {
            val ids = AppWidgetManager.getInstance(context)
                .getAppWidgetIds(ComponentName(context, javaClass))
            if (ids.isNotEmpty()) {
                onUpdate(context, AppWidgetManager.getInstance(context), ids)
            }
        }
    }
}
