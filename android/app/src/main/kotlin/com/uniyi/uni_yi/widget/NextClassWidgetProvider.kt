package com.uniyi.uni_yi.widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.text.format.DateFormat
import android.widget.RemoteViews
import com.uniyi.uni_yi.R
import es.antonborri.home_widget.HomeWidgetPlugin
import org.json.JSONArray
import java.util.Calendar
import java.util.Date

/**
 * 桌面小组件：下节课。
 *
 * 关键改造：不再让 Dart 算"哪一节是下一节"，因为 App 不开 Dart 不跑就永远停在
 * 上次推送的那一节。改成 Dart 把"未来 7 天所有课程的绝对时间"打成 JSON 推过来，
 * widget 自己每次 onUpdate 拿当前墙上时间扫一遍挑下一节。
 *
 * 触发时机：
 * 1. 系统按 updatePeriodMillis(=30min) 周期 wake；
 * 2. 我们 self-schedule 一个 AlarmManager 触发，让"当前节结束 / 下一节开始"
 *    那一刻 widget 会立刻翻面，不需要等 30 分钟。
 */
class NextClassWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        val prefs: SharedPreferences = HomeWidgetPlugin.getData(context)
        val now = System.currentTimeMillis()
        val next = pickNext(prefs.getString("next_class.plan", null), now)

        for (widgetId in appWidgetIds) {
            val views = RemoteViews(context.packageName, R.layout.next_class_widget)
            if (next != null) {
                views.setTextViewText(R.id.widget_subtitle, formatSubtitle(next.startTs, now))
                views.setTextViewText(R.id.widget_course, next.name)
                views.setTextViewText(
                    R.id.widget_time,
                    "${formatHm(next.startTs)} - ${formatHm(next.endTs)}",
                )
                views.setTextViewText(
                    R.id.widget_meta,
                    listOfNotNull(
                        next.location.takeIf { it.isNotBlank() },
                        next.teacher.takeIf { it.isNotBlank() },
                    ).joinToString(" · "),
                )
                views.setViewVisibility(R.id.widget_time, android.view.View.VISIBLE)
                views.setViewVisibility(
                    R.id.widget_meta,
                    if (next.location.isNotBlank() || next.teacher.isNotBlank())
                        android.view.View.VISIBLE
                    else android.view.View.GONE,
                )
            } else {
                renderFallback(prefs, views)
            }

            // 点击跳回 App。不设 intent.data，避免走到 GoRouter 找不到路由。
            val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            if (launchIntent != null) {
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

        // 安排下一次自动刷新：取"下一节开始 / 当前节结束"中较近的那一刻。
        scheduleNextTick(context, prefs, now)
    }

    /**
     * 用 fallback 字段（Dart 上次推送时已经写入）兜底 plan 缺失/解析失败的情况。
     */
    private fun renderFallback(prefs: SharedPreferences, views: RemoteViews) {
        val hasNext = prefs.getBoolean("next_class.has", false)
        val courseName = prefs.getString("next_class.courseName", "暂无课程信息") ?: "暂无课程信息"
        val subtitle = prefs.getString("next_class.subtitle", "") ?: ""
        val timeRange = prefs.getString("next_class.timeRange", "") ?: ""
        val location = prefs.getString("next_class.location", "") ?: ""
        val teacher = prefs.getString("next_class.teacher", "") ?: ""

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
    }

    private fun pickNext(planJson: String?, now: Long): NextClass? {
        if (planJson.isNullOrBlank()) return null
        return try {
            val arr = JSONArray(planJson)
            for (i in 0 until arr.length()) {
                val item = arr.getJSONObject(i)
                val startTs = item.optLong("ts", 0)
                val endTs = item.optLong("te", 0)
                if (startTs <= 0) continue
                // 当前节正在上 → 仍然把它作为 widget 卡片显示（用户最关心"现在/下一节"）。
                // 也可以挑严格 ts > now，但实测把"正在上的课"显示出来体验更好。
                if (endTs > now) {
                    return NextClass(
                        name = item.optString("name", ""),
                        location = item.optString("loc", ""),
                        teacher = item.optString("teacher", ""),
                        startTs = startTs,
                        endTs = endTs,
                    )
                }
            }
            null
        } catch (_: Exception) {
            null
        }
    }

    private fun scheduleNextTick(
        context: Context,
        prefs: SharedPreferences,
        now: Long,
    ) {
        val planJson = prefs.getString("next_class.plan", null) ?: return
        val nextEvent = nextEventTimestamp(planJson, now) ?: return
        // 给 5 秒缓冲，避免 alarm 触发时间还没到 plan 边界。
        val triggerAt = nextEvent + 5_000

        val intent = Intent(context, javaClass).apply {
            action = AppWidgetManager.ACTION_APPWIDGET_UPDATE
            // 提前列好 ids，receiver onReceive 直接走我们覆盖过的分支。
            val ids = AppWidgetManager.getInstance(context)
                .getAppWidgetIds(ComponentName(context, javaClass))
            putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
        }
        val pi = PendingIntent.getBroadcast(
            context,
            42,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        // 不需要精确闹钟权限的 inexact 调度即可：分钟级误差对"下节课"显示完全够用。
        am.set(AlarmManager.RTC, triggerAt, pi)
    }

    /**
     * 找出 plan 里下一个会改变 widget 文案的时间点：
     * 优先返回"还没开始"那节的 ts；如果当前正在上一节，则返回它的 te。
     */
    private fun nextEventTimestamp(planJson: String, now: Long): Long? {
        return try {
            val arr = JSONArray(planJson)
            // 第一个 ts > now 的事件
            for (i in 0 until arr.length()) {
                val item = arr.getJSONObject(i)
                val ts = item.optLong("ts", 0)
                val te = item.optLong("te", 0)
                if (te > now && ts > now) {
                    return ts
                }
                if (te > now && ts <= now) {
                    // 正在上的这节，下次要更新的时间点是它的 te
                    return te
                }
            }
            null
        } catch (_: Exception) {
            null
        }
    }

    private fun formatHm(ts: Long): String {
        val cal = Calendar.getInstance()
        cal.timeInMillis = ts
        return DateFormat.format("HH:mm", cal).toString()
    }

    private fun formatSubtitle(startTs: Long, now: Long): String {
        val cal = Calendar.getInstance()
        cal.timeInMillis = now
        val today = cal.get(Calendar.DAY_OF_YEAR)
        val nowYear = cal.get(Calendar.YEAR)

        val cls = Calendar.getInstance()
        cls.timeInMillis = startTs
        val clsDay = cls.get(Calendar.DAY_OF_YEAR)
        val clsYear = cls.get(Calendar.YEAR)

        return when {
            clsYear == nowYear && clsDay == today -> {
                if (startTs <= now) "正在上课" else "今天 ${formatHm(startTs)}"
            }
            clsYear == nowYear && clsDay == today + 1 -> "明天 ${formatHm(startTs)}"
            else -> {
                val pattern = "M/d HH:mm"
                DateFormat.format(pattern, Date(startTs)).toString()
            }
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

    private data class NextClass(
        val name: String,
        val location: String,
        val teacher: String,
        val startTs: Long,
        val endTs: Long,
    )
}
