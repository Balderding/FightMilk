package org.balderding.workout

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews

/**
 * Batch 23, F351: the home-screen widget. It shows the lines the app last gave it (the next
 * workout and this week, no body numbers), kept in this app's own preferences, and its two
 * buttons only open a screen in the app (like the shortcuts). Nothing is fetched from anywhere.
 */
class FmWidget : AppWidgetProvider() {
    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) = render(context, manager, ids)

    companion object {
        private const val PREFS = "fm_widget"

        fun ids(ctx: Context): IntArray = AppWidgetManager.getInstance(ctx).getAppWidgetIds(ComponentName(ctx, FmWidget::class.java))

        /** Keeps the lines and redraws; nothing is kept when no widget is on the home screen. */
        fun save(ctx: Context, next: String, week: String): Boolean {
            val ids = ids(ctx)
            if (ids.isEmpty()) {
                ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().clear().apply()
                return false
            }
            ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString("next", next.take(200)).putString("week", week.take(120)).apply()
            render(ctx, AppWidgetManager.getInstance(ctx), ids)
            return true
        }

        private fun open(ctx: Context, go: String, code: Int): PendingIntent {
            val i = Intent(ctx, MainActivity::class.java).setAction(MainActivity.SHORTCUT).putExtra("go", go).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            return PendingIntent.getActivity(ctx, code, i, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        }

        fun render(ctx: Context, manager: AppWidgetManager, ids: IntArray) {
            val p = ctx.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            for (id in ids) {
                val v = RemoteViews(ctx.packageName, R.layout.fm_widget)
                v.setTextViewText(R.id.next, p.getString("next", null) ?: ctx.getString(R.string.widget_empty))
                v.setTextViewText(R.id.week, p.getString("week", null) ?: "")
                v.setOnClickPendingIntent(R.id.root, open(ctx, "today", 1))
                v.setOnClickPendingIntent(R.id.open, open(ctx, "today", 1))
                v.setOnClickPendingIntent(R.id.weight, open(ctx, "weight", 2))
                manager.updateAppWidget(id, v)
            }
        }
    }
}
