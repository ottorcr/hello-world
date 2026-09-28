package com.ottorcr.random_thoughts

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetPlugin
import es.antonborri.home_widget.HomeWidgetProvider
import java.net.HttpURLConnection
import java.net.URL
import org.json.JSONArray
import org.json.JSONObject

/**
 * Home-screen widget that shows one random thought.
 *
 * On every update it redraws from the cache the Flutter app saved, then pulls
 * fresh thoughts from the Firestore REST API in the background. Tapping
 * "Shuffle" picks another one; tapping the thought opens the app.
 */
class ThoughtsWidgetProvider : HomeWidgetProvider() {

  override fun onUpdate(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      widgetData: SharedPreferences,
  ) {
    render(context, appWidgetManager, appWidgetIds, widgetData)

    val projectId = widgetData.getString(KEY_PROJECT_ID, null) ?: return
    val pending = goAsync()
    Thread {
      try {
        val fresh = fetchThoughts(projectId)
        if (fresh != null) {
          widgetData.edit().putString(KEY_THOUGHTS, JSONArray(fresh).toString()).apply()
          render(context, appWidgetManager, appWidgetIds, widgetData)
        }
      } finally {
        pending.finish()
      }
    }.start()
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
    val thoughts = readCache(data)
    val shuffleIntent =
        PendingIntent.getBroadcast(
            context,
            0,
            Intent(context, ThoughtsWidgetProvider::class.java).setAction(ACTION_SHUFFLE),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    val openApp = HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java)

    for (id in ids) {
      val views =
          RemoteViews(context.packageName, R.layout.thoughts_widget).apply {
            setTextViewText(
                R.id.thought_text,
                thoughts.randomOrNull() ?: context.getString(R.string.widget_empty),
            )
            setOnClickPendingIntent(R.id.thought_text, openApp)
            setOnClickPendingIntent(R.id.shuffle_button, shuffleIntent)
          }
      manager.updateAppWidget(id, views)
    }
  }

  private fun readCache(data: SharedPreferences): List<String> {
    val raw = data.getString(KEY_THOUGHTS, null) ?: return emptyList()
    return try {
      val array = JSONArray(raw)
      List(array.length()) { array.getString(it) }.filter { it.isNotBlank() }
    } catch (e: Exception) {
      emptyList()
    }
  }

  /** Returns the latest thoughts, or null if the request failed. */
  private fun fetchThoughts(projectId: String): List<String>? {
    val url =
        URL(
            "https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)" +
                "/documents/thoughts?pageSize=200&orderBy=createdAt%20desc")
    val conn = url.openConnection() as HttpURLConnection
    return try {
      conn.connectTimeout = 4000
      conn.readTimeout = 4000
      if (conn.responseCode != 200) return null
      val body = conn.inputStream.bufferedReader().use { it.readText() }
      val docs = JSONObject(body).optJSONArray("documents") ?: return emptyList()
      List(docs.length()) { i ->
            docs
                .getJSONObject(i)
                .optJSONObject("fields")
                ?.optJSONObject("text")
                ?.optString("stringValue")
                .orEmpty()
          }
          .filter { it.isNotBlank() }
    } catch (e: Exception) {
      null
    } finally {
      conn.disconnect()
    }
  }

  companion object {
    private const val ACTION_SHUFFLE = "com.ottorcr.random_thoughts.SHUFFLE"
    // Keys shared with lib/widget_sync.dart.
    private const val KEY_THOUGHTS = "thoughts_json"
    private const val KEY_PROJECT_ID = "firebase_project_id"
  }
}
