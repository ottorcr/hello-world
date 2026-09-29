import 'dart:convert';

import 'package:http/http.dart' as http;

import 'repository.dart';

/// A Spotify track attached to a thought.
///
/// We only store the track id, its title, and (optionally) the cover art URL
/// from Spotify's own image CDN. Nobody needs a Spotify account: tapping the
/// song opens it in the Spotify app, or on the web.
class Song {
  const Song({required this.id, required this.title, this.art});

  final String id;
  final String title;
  final String? art;

  Uri get url => Uri.parse('https://open.spotify.com/track/$id');

  Map<String, String> toMap() => {'id': id, 'title': title, 'art': ?art};

  /// Reads a song from Firestore data, ignoring anything malformed.
  static Song? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final title = raw['title'];
    if (id is! String || !_trackId.hasMatch(id)) return null;
    if (title is! String || title.isEmpty) return null;
    final art = raw['art'];
    return Song(
      id: id,
      title: title,
      art: art is String && isSpotifyArt(art) ? art : null,
    );
  }
}

final _trackId = RegExp(r'^[A-Za-z0-9]{22}$');

/// Finds a Spotify track id in a pasted link or URI, for example
/// `https://open.spotify.com/track/4cOdK2wGLETKBW3PvgPWqT?si=...`,
/// `https://open.spotify.com/intl-es/track/...` or `spotify:track:...`.
String? parseSpotifyTrackId(String input) {
  final match = RegExp(
    r'(?:https?://open\.spotify\.com/(?:intl-[a-zA-Z-]+/)?track/|spotify:track:)([A-Za-z0-9]{22})(?![A-Za-z0-9])',
  ).firstMatch(input.trim());
  return match?.group(1);
}

/// Cover art must come from Spotify's image CDN. The security rules enforce
/// the same pattern, so a friend can't slip in a tracking pixel.
bool isSpotifyArt(String url) => RegExp(
  r'^https://(i\.scdn\.co|image-cdn-[a-z]{2}\.spotifycdn\.com)/image/[A-Za-z0-9]{1,64}$',
).hasMatch(url);

/// Looks up a track's title and cover art with Spotify's public oEmbed
/// endpoint (no API key or login needed).
Future<Song> lookUpSong(String trackId, {http.Client? client}) async {
  final uri = Uri.https('open.spotify.com', '/oembed', {
    'url': 'https://open.spotify.com/track/$trackId',
  });
  final c = client ?? http.Client();
  try {
    final res = await c.get(uri).timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) {
      throw const UserFacingException('Spotify doesn’t know that song.');
    }
    final data = jsonDecode(res.body);
    final title = (data is Map ? data['title'] : null) as String?;
    if (title == null || title.trim().isEmpty) {
      throw const UserFacingException('Spotify doesn’t know that song.');
    }
    final art = data['thumbnail_url'];
    final clipped = title.trim().runes.length > 200
        ? String.fromCharCodes(title.trim().runes.take(200))
        : title.trim();
    return Song(
      id: trackId,
      title: clipped,
      art: art is String && isSpotifyArt(art) ? art : null,
    );
  } on UserFacingException {
    rethrow;
  } catch (_) {
    throw const UserFacingException(
      'Couldn’t reach Spotify. Check your connection.',
    );
  } finally {
    if (client == null) c.close();
  }
}
