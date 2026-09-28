import 'dart:convert';

import 'package:home_widget/home_widget.dart';

import 'thought.dart';

/// Shares data with the native home-screen widgets.
///
/// The widgets read two keys from shared storage (App Group UserDefaults on
/// iOS, SharedPreferences on Android):
///  * [thoughtsKey]: JSON array of strings, an offline cache of thoughts.
///  * [projectIdKey]: the Firebase project ID, so widgets can pull fresh
///    thoughts from the Firestore REST API on their own, without the app open.
class WidgetSync {
  static const appGroupId = 'group.com.ottorcr.randomThoughts';
  static const iOSWidgetKind = 'ThoughtsWidget';
  static const androidWidgetName = 'ThoughtsWidgetProvider';

  static const thoughtsKey = 'thoughts_json';
  static const projectIdKey = 'firebase_project_id';

  static Future<void> init(String projectId) async {
    await HomeWidget.setAppGroupId(appGroupId);
    await HomeWidget.saveWidgetData<String>(projectIdKey, projectId);
  }

  static Future<void> push(List<Thought> thoughts) async {
    final texts = thoughts
        .map((t) => t.text)
        .where((t) => t.isNotEmpty)
        .toList(growable: false);
    await HomeWidget.saveWidgetData<String>(thoughtsKey, jsonEncode(texts));
    await HomeWidget.updateWidget(
      iOSName: iOSWidgetKind,
      androidName: androidWidgetName,
    );
  }
}
