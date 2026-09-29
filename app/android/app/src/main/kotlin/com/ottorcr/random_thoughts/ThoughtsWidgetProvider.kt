package com.ottorcr.random_thoughts

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import java.io.File
import org.json.JSONArray

/**
 * Home-screen widget that shows one random thought from a friend.
 *
 * It never touches the network. It only reads the feed the app saved on
 * this device (see lib/widget_sync.dart). If that copy is older than
 * [STALE_AFTER_MS], it asks the app to refresh it in the background with
 * the user's own sign-in.
 */
class ThoughtsWidgetProvider : HomeWidgetProvider() {

  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    render(context, appWidgetManager, appWidgetIds, widgetData)

    val syncedAt = (widgetData.all[KEY_SYNCED_AT] as? Number)?.toLong() ?: 0L
    if (System.currentTimeMillis() - syncedAt > STALE_AFTER_MS) {
      try {
        HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse("randomthoughts://refresh"))
            .send()
      } catch (e: PendingIntent.CanceledException) {
        // Nothing to do; the next update will try again.
      }
    }
  }

  override fun onReceive(context: Context, intent: Intent) {
    if (intent.action == ACTION_SHUFFLE) {
      val manager = AppWidgetManager.getInstance(context)
      val ids = manager.getAppWidgetIds(ComponentName(context, javaClass))
      render(context, manager, ids, HomeWidgetPlugin.getData(context))
      return
    }
    super.onReceive(context, intent)
  }

  private fun render(
      context: Context,
      manager: AppWidgetManager,
      ids: IntArray,
      data: SharedPreferences,
  ) {
    val shuffle =
        PendingIntent.getBroadcast(
            context,
            0,
            Intent(context, ThoughtsWidgetProvider::class.java).setAction(ACTION_SHUFFLE),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    val openApp = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)
    val feed = readFeed(data)

    for (id in ids) {
      val item = feed.randomOrNull()
      val photo = item?.imagePath?.let { loadBitmap(it) }
      val layout = if (photo != null) R.layout.thoughts_widget_photo else R.layout.thoughts_widget
      val views =
          RemoteViews(context.packageName, layout).apply {
            setTextViewText(
                R.id.header,
                if (item == null) context.getString(R.string.widget_header)
                else context.getString(R.string.widget_from, item.author),
            )
            val text = item?.text ?: context.getString(R.string.widget_empty)
            setTextViewText(R.id.thought_text, text)
            setViewVisibility(R.id.thought_text, if (text.isEmpty()) View.GONE else View.VISIBLE)
            if (photo != null) setImageViewBitmap(R.id.photo, photo)
            val song = item?.song
            if (song != null) {
              setTextViewText(R.id.song, context.getString(R.string.widget_song, song.title))
              setViewVisibility(R.id.song, View.VISIBLE)
              setOnClickPendingIntent(R.id.song, openSong(context, song.url))
            } else {
              setViewVisibility(R.id.song, View.GONE)
            }
            setOnClickPendingIntent(R.id.content, openApp)
            setOnClickPendingIntent(R.id.shuffle_button, shuffle)
          }
      manager.updateAppWidget(id, views)
    }
  }

  private data class Song(val title: String, val url: String)

  private data class Item(
      val author: String,
      val text: String,
      val imagePath: String?,
      val song: Song?,
  )

  /** Opens the song in Spotify (or the browser). Only Spotify track links are allowed. */
  private fun openSong(context: Context, url: String): PendingIntent =
      PendingIntent.getActivity(
          context,
          url.hashCode(),
          Intent(Intent.ACTION_VIEW, Uri.parse(url)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
          PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
      )

  private fun readFeed(data: SharedPreferences): List<Item> {
    val raw = data.getString(KEY_FEED, null) ?: return emptyList()
    return try {
      val array = JSONArray(raw)
      List(array.length()) { i ->
        val o = array.getJSONObject(i)
        val songUrl = o.optString("u")
        val song =
            if (SPOTIFY_TRACK.matches(songUrl)) Song(o.optString("s"), songUrl) else null
        Item(o.optString("a"), o.optString("t"), o.optString("i").ifEmpty { null }, song)
      }
    } catch (e: Exception) {
      emptyList()
    }
  }

  /** Decodes a downscaled copy, so it stays under the widget's bitmap memory limit. */
  private fun loadBitmap(path: String): Bitmap? {
    if (!File(path).exists()) return null
    val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
    BitmapFactory.decodeFile(path, bounds)
    var sample = 1
    while (bounds.outWidth / (sample * 2) >= MAX_BITMAP_SIDE ||
        bounds.outHeight / (sample * 2) >= MAX_BITMAP_SIDE) {
      sample *= 2
    }
    return BitmapFactory.decodeFile(path, BitmapFactory.Options().apply { inSampleSize = sample })
  }

  companion object {
    private const val ACTION_SHUFFLE = "com.ottorcr.random_thoughts.SHUFFLE"
    private const val STALE_AFTER_MS = 25 * 60 * 1000L
    private const val MAX_BITMAP_SIDE = 640
    private val SPOTIFY_TRACK = Regex("^https://open\\.spotify\\.com/track/[A-Za-z0-9]{22}$")
    // Keys shared with lib/widget_sync.dart.
    private const val KEY_FEED = "feed_json"
    private const val KEY_SYNCED_AT = "synced_at"
  }
}
