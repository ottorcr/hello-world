import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../data/spotify.dart';
import 'common.dart';

const spotifyGreen = Color(0xFF1DB954);

/// Opens the song in the Spotify app, or in the browser if it isn't installed.
Future<void> openSong(BuildContext context, Song song) async {
  final ok = await launchUrl(song.url, mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) toast(context, 'Couldn’t open Spotify.');
}

/// A compact song card. Tap to play on Spotify.
class SongTile extends StatelessWidget {
  const SongTile({
    super.key,
    required this.song,
    this.onRemove,
    this.dense = false,
  });

  final Song song;
  final VoidCallback? onRemove;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final size = dense ? 40.0 : 56.0;
    return Material(
      color: scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openSong(context, song),
        child: Row(
          children: [
            SizedBox.square(
              dimension: size,
              child: song.art == null
                  ? const ColoredBox(
                      color: spotifyGreen,
                      child: Icon(Icons.music_note, color: Colors.white),
                    )
                  : Image.network(
                      song.art!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const ColoredBox(
                        color: spotifyGreen,
                        child: Icon(Icons.music_note, color: Colors.white),
                      ),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    song.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (!dense)
                    Text(
                      'Play on Spotify',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            if (onRemove != null)
              IconButton(
                tooltip: 'Remove song',
                onPressed: onRemove,
                icon: const Icon(Icons.close),
              )
            else
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Icon(Icons.play_circle_fill, color: spotifyGreen),
              ),
          ],
        ),
      ),
    );
  }
}

/// Asks for a Spotify song link and looks it up. Pre-fills the field if the
/// clipboard already holds one (Spotify → Share → Copy song link).
Future<Song?> pickSong(BuildContext context) async {
  final clip = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
  if (!context.mounted) return null;
  return showDialog<Song>(
    context: context,
    builder: (_) => _SongDialog(
      initial: parseSpotifyTrackId(clip) != null ? clip.trim() : '',
    ),
  );
}

class _SongDialog extends StatefulWidget {
  const _SongDialog({required this.initial});

  final String initial;

  @override
  State<_SongDialog> createState() => _SongDialogState();
}

class _SongDialogState extends State<_SongDialog> {
  late final _link = TextEditingController(text: widget.initial);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _lookUp() async {
    final id = parseSpotifyTrackId(_link.text);
    if (id == null) {
      setState(
        () => _error = 'Paste a Spotify song link (open.spotify.com/track/…).',
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final song = await lookUpSong(id);
      if (mounted) Navigator.pop(context, song);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = errorText(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.music_note, color: spotifyGreen),
          SizedBox(width: 8),
          Text('Add a song'),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'In Spotify, tap ⋯ on a song → Share → Copy song link, then paste it here.',
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _link,
            autofocus: widget.initial.isEmpty,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              hintText: 'https://open.spotify.com/track/…',
              errorText: _error,
              errorMaxLines: 3,
              suffixIcon: IconButton(
                tooltip: 'Paste',
                icon: const Icon(Icons.content_paste),
                onPressed: () async {
                  final text = (await Clipboard.getData(Clipboard.kTextPlain))
                      ?.text;
                  if (text != null) _link.text = text.trim();
                },
              ),
            ),
            onSubmitted: (_) => _lookUp(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _lookUp,
          child: _busy
              ? const SizedBox.square(
                  dimension: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Add'),
        ),
      ],
    );
  }
}
