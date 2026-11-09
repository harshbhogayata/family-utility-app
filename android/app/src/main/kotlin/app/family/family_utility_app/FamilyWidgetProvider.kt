package app.family.family_utility_app

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.View
import android.widget.RemoteViews

/// 112 Widgets: the Family home-screen widget. It reads the snapshot the app
/// wrote (next medicine, speed-dial numbers) from local preferences only.
class FamilyWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
        for (id in ids) {
            manager.updateAppWidget(id, build(context))
        }
    }

    companion object {
        const val PREFS = "family_home_widget"
        const val ACTION_WIDGET = "app.family.WIDGET_ACTION"
        const val EXTRA_ACTION = "widget_action"

        private val dialIds = intArrayOf(R.id.widget_dial_0, R.id.widget_dial_1, R.id.widget_dial_2)

        /// Saves the app's snapshot and redraws every placed widget.
        fun publish(context: Context, data: Map<String, String>) {
            val editor = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            editor.clear()
            for ((k, v) in data) {
                editor.putString(k, v)
            }
            editor.apply()
            refreshAll(context)
        }

        fun refreshAll(context: Context) {
            val manager = AppWidgetManager.getInstance(context)
            val ids = manager.getAppWidgetIds(ComponentName(context, FamilyWidgetProvider::class.java))
            for (id in ids) {
                manager.updateAppWidget(id, build(context))
            }
        }

        /// The intent that opens the app on [action] ("scan", "paste", "medicine").
        fun launchIntent(context: Context, action: String): Intent {
            val intent = Intent(context, MainActivity::class.java)
            intent.action = ACTION_WIDGET
            intent.putExtra(EXTRA_ACTION, "familyapp://widget/" + action)
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            return intent
        }

        private fun open(context: Context, action: String, code: Int): PendingIntent =
            PendingIntent.getActivity(
                context,
                code,
                launchIntent(context, action),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )

        fun build(context: Context): RemoteViews {
            val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            val views = RemoteViews(context.packageName, R.layout.family_widget)
            val title = prefs.getString("medicine_title", null)
                ?: context.getString(R.string.widget_no_medicine)
            val detail = prefs.getString("medicine_detail", "") ?: ""
            val medicine = if (detail.isEmpty()) title else "$title · $detail"
            views.setTextViewText(R.id.widget_medicine, medicine)
            views.setContentDescription(R.id.widget_medicine, "Next medicine: $medicine")
            views.setOnClickPendingIntent(R.id.widget_medicine, open(context, "medicine", 1120))
            views.setOnClickPendingIntent(R.id.widget_scan, open(context, "scan", 1121))
            views.setOnClickPendingIntent(R.id.widget_paste, open(context, "paste", 1122))
            for (i in dialIds.indices) {
                val label = prefs.getString("dial_${i}_label", "") ?: ""
                val number = prefs.getString("dial_${i}_number", "") ?: ""
                val viewId = dialIds[i]
                if (label.isEmpty() || number.isEmpty()) {
                    views.setViewVisibility(viewId, View.GONE)
                    continue
                }
                views.setViewVisibility(viewId, View.VISIBLE)
                views.setTextViewText(viewId, label)
                views.setContentDescription(viewId, "Call $label")
                val dial = Intent(Intent.ACTION_DIAL, Uri.parse("tel:" + number))
                dial.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                views.setOnClickPendingIntent(
                    viewId,
                    PendingIntent.getActivity(
                        context,
                        1130 + i,
                        dial,
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                    )
                )
            }
            return views
        }
    }
}
