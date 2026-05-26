package com.uniyi.uni_yi.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import android.widget.RemoteViews
import com.uniyi.uni_yi.R
import es.antonborri.home_widget.HomeWidgetPlugin
import java.io.File

/**
 * 整周课表小组件。
 *
 * 思路上和 NextClassWidgetProvider 不一样：这次的视图全部由 Flutter 端渲染
 * 成 PNG 落盘，原生这边只负责把它放进 ImageView。
 *
 * - 数据 key 在 Dart 那边的 HomeWidgetService 里维护。
 * - 没数据 / PNG 不存在时切到一个空态文本。
 */
class WeekScheduleWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val prefs = HomeWidgetPlugin.getData(context)
        val hasData = prefs.getBoolean("week_schedule.hasData", false)
        val imagePath = prefs.getString("week_schedule.imagePath", null)

        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.week_schedule_widget)

            if (hasData && !imagePath.isNullOrBlank() && File(imagePath).exists()) {
                // 直接 decode 文件。home_widget 的 PNG 落在 cache dir，
                // 体积不大（~50 KB），同步 decode 没压力。
                val bitmap = BitmapFactory.decodeFile(imagePath)
                if (bitmap != null) {
                    views.setImageViewBitmap(R.id.widget_image, bitmap)
                    views.setViewVisibility(R.id.widget_image, android.view.View.VISIBLE)
                    views.setViewVisibility(R.id.widget_empty, android.view.View.GONE)
                } else {
                    showEmpty(views)
                }
            } else {
                showEmpty(views)
            }

            // 点击跳回 App 课表分支。
            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (launchIntent != null) {
                launchIntent.data = Uri.parse("uniyi://widget/week-schedule")
                val pi = PendingIntent.getActivity(
                    context,
                    1,
                    launchIntent,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                )
                views.setOnClickPendingIntent(R.id.widget_root, pi)
            }

            appWidgetManager.updateAppWidget(widgetId, views)
        }
    }

    private fun showEmpty(views: RemoteViews) {
        views.setViewVisibility(R.id.widget_image, android.view.View.GONE)
        views.setViewVisibility(R.id.widget_empty, android.view.View.VISIBLE)
        views.setTextViewText(R.id.widget_empty, "课表加载中…\n打开应用同步一次后即可显示")
    }

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
