package com.runspot.runquest

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.View
import android.widget.RemoteViews

/**
 * 홈 화면 위젯입니다. 이번 주 달린 거리와 주간 목표 막대를 보여 주고,
 * '러닝 시작'을 누르면 앱을 열어 3·2·1 카운트다운부터 바로 시작합니다.
 * 내용은 앱이 기록·목표를 바꿀 때마다 [save]로 넘겨 줍니다.
 */
class RunWidgetProvider : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) manager.updateAppWidget(id, views(context))
    }

    companion object {
        private const val PREFS = "runspot_home_widget"

        /** 앱이 보낸 이번 주 기록을 저장하고 놓여 있는 위젯을 모두 새로 그립니다. */
        fun save(context: Context, weekKm: String, goalKm: Int, percent: Int, runs: Int) {
            context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
                .putString("week_km", weekKm)
                .putInt("goal_km", goalKm)
                .putInt("percent", percent)
                .putInt("runs", runs)
                .apply()
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, RunWidgetProvider::class.java))
            for (id in ids) manager.updateAppWidget(id, views(context))
        }

        private fun views(context: Context): RemoteViews {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val views = RemoteViews(context.packageName, R.layout.run_widget)
            val weekKm = prefs.getString("week_km", null)
            if (weekKm != null) {
                val goal = prefs.getInt("goal_km", 0)
                val percent = prefs.getInt("percent", 0).coerceIn(0, 100)
                val runs = prefs.getInt("runs", 0)
                views.setTextViewText(R.id.widget_distance, "$weekKm km")
                if (goal > 0) {
                    val status = if (percent >= 100) "목표 달성!" else "$percent%"
                    views.setTextViewText(R.id.widget_goal, "목표 ${goal}km · $status")
                    views.setProgressBar(R.id.widget_progress, 100, percent, false)
                    views.setViewVisibility(R.id.widget_progress, View.VISIBLE)
                } else {
                    views.setTextViewText(
                        R.id.widget_goal,
                        if (runs > 0) "이번 주 ${runs}번 달렸어요" else "이번 주 첫 러닝을 시작해요",
                    )
                    views.setViewVisibility(R.id.widget_progress, View.GONE)
                }
            }
            views.setOnClickPendingIntent(R.id.widget_root, link(context, "runspot://home", 1))
            views.setOnClickPendingIntent(R.id.widget_start, link(context, "runspot://run/start", 2))
            return views
        }

        /** 앱을 열면서 무엇을 할지(홈 열기·러닝 시작) 링크로 알려 줍니다. */
        private fun link(context: Context, uri: String, code: Int): PendingIntent {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(uri), context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            return PendingIntent.getActivity(
                context,
                code,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }
}
