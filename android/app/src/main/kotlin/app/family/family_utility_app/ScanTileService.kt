package app.family.family_utility_app

import android.annotation.SuppressLint
import android.app.PendingIntent
import android.content.Context
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService

/// 112 Widgets: quick-settings tile. Tap opens the document scanner; the
/// subtitle shows the next medicine (Android 10+).
class ScanTileService : TileService() {

    override fun onStartListening() {
        super.onStartListening()
        val tile = qsTile ?: return
        tile.state = Tile.STATE_INACTIVE
        tile.label = getString(R.string.scan_tile_label)
        if (Build.VERSION.SDK_INT >= 29) {
            val prefs = getSharedPreferences(FamilyWidgetProvider.PREFS, Context.MODE_PRIVATE)
            val title = prefs.getString("medicine_title", "") ?: ""
            val detail = prefs.getString("medicine_detail", "") ?: ""
            tile.subtitle = if (detail.isEmpty()) title else detail
        }
        tile.updateTile()
    }

    @SuppressLint("StartActivityAndCollapseDeprecated")
    override fun onClick() {
        super.onClick()
        val intent = FamilyWidgetProvider.launchIntent(this, "scan")
        if (Build.VERSION.SDK_INT >= 34) {
            val pending = PendingIntent.getActivity(
                this,
                1140,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
            )
            startActivityAndCollapse(pending)
        } else {
            @Suppress("DEPRECATION")
            startActivityAndCollapse(intent)
        }
    }
}
