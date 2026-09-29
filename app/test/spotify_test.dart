import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:random_thoughts/data/repository.dart';
import 'package:random_thoughts/data/spotify.dart';

void main() {
  const id = '4cOdK2wGLETKBW3PvgPWqT';

  group('parseSpotifyTrackId', () {
    test('accepts the links Spotify shares', () {
      for (final link in [
        'https://open.spotify.com/track/$id',
        'https://open.spotify.com/track/$id?si=abc123',
        'https://open.spotify.com/intl-es/track/$id?si=x',
        'spotify:track:$id',
        '  Listen to this! https://open.spotify.com/track/$id  ',
      ]) {
        expect(parseSpotifyTrackId(link), id, reason: link);
      }
    });

    test('rejects anything else', () {
      for (final link in [
        '',
        'https://open.spotify.com/album/$id',
        'https://open.spotify.com/playlist/$id',
        'https://evil.example/track/$id',
        'https://open.spotify.com.evil.example/track/$id',
        'https://open.spotify.com/track/${id}EXTRA',
        'https://open.spotify.com/track/short',
      ]) {
        expect(parseSpotifyTrackId(link), isNull, reason: link);
      }
    });
  });

  test('isSpotifyArt only allows Spotify image CDN URLs', () {
    expect(isSpotifyArt('https://i.scdn.co/image/ab67616d0000b273abc'), isTrue);
    expect(
      isSpotifyArt('https://image-cdn-ak.spotifycdn.com/image/ab67'),
      isTrue,
    );
    expect(isSpotifyArt('http://i.scdn.co/image/abc'), isFalse);
    expect(isSpotifyArt('https://evil.example/image/abc'), isFalse);
    expect(isSpotifyArt('https://i.scdn.co/image/abc?x=1'), isFalse);
  });

  test('Song.fromMap ignores malformed data', () {
    expect(Song.fromMap(null), isNull);
    expect(Song.fromMap({'id': 'bad', 'title': 'x'}), isNull);
    expect(Song.fromMap({'id': id, 'title': ''}), isNull);
    final s = Song.fromMap({
      'id': id,
      'title': 'T',
      'art': 'https://evil.example/x',
    })!;
    expect(s.art, isNull);
    expect(s.url.toString(), 'https://open.spotify.com/track/$id');
  });

  group('lookUpSong', () {
    test('reads title and art from oEmbed', () async {
      late Uri requested;
      final client = MockClient((req) async {
        requested = req.url;
        return http.Response(
          jsonEncode({
            'title': 'Never Gonna Give You Up',
            'thumbnail_url': 'https://i.scdn.co/image/ab67616d00001e02abc',
          }),
          200,
        );
      });
      final song = await lookUpSong(id, client: client);
      expect(requested.host, 'open.spotify.com');
      expect(requested.path, '/oembed');
      expect(song.title, 'Never Gonna Give You Up');
      expect(song.art, 'https://i.scdn.co/image/ab67616d00001e02abc');
      expect(song.toMap(), {
        'id': id,
        'title': 'Never Gonna Give You Up',
        'art': song.art,
      });
    });

    test('drops art that is not on the Spotify CDN', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'title': 'Song',
            'thumbnail_url': 'https://evil.example/p.png',
          }),
          200,
        ),
      );
      final song = await lookUpSong(id, client: client);
      expect(song.art, isNull);
      expect(song.toMap().containsKey('art'), isFalse);
    });

    test('unknown songs and network errors give friendly messages', () async {
      final notFound = MockClient((_) async => http.Response('nope', 404));
      await expectLater(
        lookUpSong(id, client: notFound),
        throwsA(isA<UserFacingException>()),
      );
      final offline = MockClient(
        (_) async => throw http.ClientException('offline'),
      );
      await expectLater(
        lookUpSong(id, client: offline),
        throwsA(isA<UserFacingException>()),
      );
    });
  });
}
