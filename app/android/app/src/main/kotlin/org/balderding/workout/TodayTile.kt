package org.balderding.workout

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.service.quicksettings.Tile
import android.service.quicksettings.TileService
import androidx.annotation.RequiresApi

/**
 * Batch 23, F353: a Quick Settings tile that opens today's workout (the same as the "Today's
 * workout" shortcut). It only opens the app; nothing is started or saved from the shade.
 */
@RequiresApi(Build.VERSION_CODES.N)
class TodayTile : TileService() {
    override fun onStartListening() {
        super.onStartListening()
        qsTile?.let {
            it.state = Tile.STATE_INACTIVE
            it.label = getString(R.string.tile_label)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) it.subtitle = getString(R.string.tile_sub)
            it.updateTile()
        }
    }

    override fun onClick() {
        super.onClick()
        val open = {
            val i = Intent(this, MainActivity::class.java)
                .setAction(MainActivity.SHORTCUT)
                .putExtra("go", "today")
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (Build.VERSION.SDK_INT >= 34) {
                startActivityAndCollapse(PendingIntent.getActivity(this, 0, i, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT))
            } else {
                @Suppress("DEPRECATION")
                startActivityAndCollapse(i)
            }
        }
        if (isLocked) unlockAndRun { open() } else open()
    }
}
