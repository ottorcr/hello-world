import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:home_widget/home_widget.dart';

import 'data/models.dart';
import 'data/repository.dart';
import 'firebase_options.dart';

/// Shares the signed-in user's feed with the native home-screen widgets.
///
/// The widgets never talk to the network. They only read what this class
/// writes to on-device storage (App Group on iOS, SharedPreferences on
/// Android):
///  * [feedKey]: JSON list of
///    `{a: author, t: text, i: imagePath?, s: songTitle?, u: songUrl?}`
///  * [syncedAtKey]: when the feed was last refreshed (ms since epoch)
class WidgetSync {
  static const appGroupId = 'group.com.ottorcr.randomThoughts';
  static const iOSWidgetKind = 'ThoughtsWidget';
  static const androidWidgetName = 'ThoughtsWidgetProvider';

  static const feedKey = 'feed_json';
  static const syncedAtKey = 'synced_at';

  /// Posts with photos the widget keeps on disk.
  static const _maxImages = 12;
  static const _imageKeysKey = 'image_keys';

  static Future<void> init() async {
    await HomeWidget.setAppGroupId(appGroupId);
    await HomeWidget.registerInteractivityCallback(backgroundRefresh);
  }

  static Future<void> push(List<Post> posts, Repository repo) async {
    final items = <Map<String, String>>[];
    final imageKeys = <String>[];
    for (final post in posts) {
      String? path;
      if (post.hasImage && imageKeys.length < _maxImages) {
        final bytes = await repo.image(post.id);
        if (bytes != null) {
          final key = 'img_${post.id}';
          path = await _saveImage(key, bytes);
          imageKeys.add(key);
        }
      }
      final song = post.song;
      if (post.text.isEmpty && path == null && song == null) continue;
      items.add({
        'a': post.authorName,
        't': post.text,
        'i': ?path,
        's': ?song?.title,
        'u': ?song?.url.toString(),
      });
    }
    await HomeWidget.saveWidgetData<String>(feedKey, jsonEncode(items));
    await HomeWidget.saveWidgetData<int>(
      syncedAtKey,
      DateTime.now().millisecondsSinceEpoch,
    );
    await _replaceImageKeys(imageKeys);
    await _reload();
  }

  /// Wipes everything the widget shows. Call it on sign-out and account
  /// deletion.
  static Future<void> clear() async {
    await HomeWidget.saveWidgetData<String>(feedKey, null);
    await HomeWidget.saveWidgetData<int>(syncedAtKey, null);
    await _replaceImageKeys(const []);
    await _reload();
  }

  static Future<void> _reload() => HomeWidget.updateWidget(
    iOSName: iOSWidgetKind,
    androidName: androidWidgetName,
  );

  static Future<String> _saveImage(String key, Uint8List bytes) async {
    final existing = await HomeWidget.getWidgetData<String>(key);
    if (existing != null && await File(existing).exists()) return existing;
    return HomeWidget.saveFile(key, bytes, extension: 'jpg');
  }

  /// Records which photo files are in use, and deletes the ones that aren't.
  /// Setting a saveFile key to null also deletes its file.
  static Future<void> _replaceImageKeys(List<String> keys) async {
    final raw = await HomeWidget.getWidgetData<String>(_imageKeysKey);
    final old = raw == null
        ? const <String>[]
        : List<String>.from(jsonDecode(raw) as List);
    for (final key in old.where((k) => !keys.contains(k))) {
      await HomeWidget.saveWidgetData<String>(key, null);
    }
    await HomeWidget.saveWidgetData<String>(_imageKeysKey, jsonEncode(keys));
  }
}

/// Runs in the background when the Android widget asks for fresh data
/// (roughly every 30 minutes). It uses the saved sign-in, so it only ever
/// sees this user's own inbox.
@pragma('vm:entry-point')
Future<void> backgroundRefresh(Uri? uri) async {
  if (uri?.host != 'refresh') return;
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await HomeWidget.setAppGroupId(WidgetSync.appGroupId);
  final user = await FirebaseAuth.instance.authStateChanges().first;
  if (user == null) {
    await WidgetSync.clear();
    return;
  }
  final repo = Repository(user.uid);
  await WidgetSync.push(await repo.fetchInbox(), repo);
}
