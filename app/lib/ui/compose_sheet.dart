import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../config.dart';
import '../data/image_prep.dart';
import '../data/repository.dart';
import '../data/spotify.dart';
import 'common.dart';
import 'song_widgets.dart';

/// Write a thought, optionally with a photo and/or a Spotify song, and send
/// it to all friends.
class ComposeSheet extends StatefulWidget {
  const ComposeSheet({
    super.key,
    required this.repo,
    required this.friendCount,
  });

  final Repository repo;
  final int friendCount;

  @override
  State<ComposeSheet> createState() => _ComposeSheetState();
}

class _ComposeSheetState extends State<ComposeSheet> {
  final _text = TextEditingController();
  Uint8List? _photo;
  Song? _song;
  bool _busy = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _pick(ImageSource source) async {
    final picked = await ImagePicker().pickImage(
      source: source,
      maxWidth: 2048,
      maxHeight: 2048,
      imageQuality: 90,
    );
    if (picked == null) return;
    setState(() => _busy = true);
    try {
      final prepared = await preparePhoto(await picked.readAsBytes());
      setState(() => _photo = prepared);
    } catch (e) {
      if (mounted) toast(context, errorText(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addSong() async {
    final song = await pickSong(context);
    if (song != null && mounted) setState(() => _song = song);
  }

  Future<void> _send() async {
    setState(() => _busy = true);
    try {
      final count = await widget.repo.send(
        text: _text.text,
        jpeg: _photo,
        song: _song,
      );
      if (!mounted) return;
      Navigator.pop(context);
      toast(context, 'Sent to $count ${count == 1 ? 'friend' : 'friends'} ✨');
    } catch (e) {
      if (mounted) {
        toast(context, errorText(e));
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canSend =
        !_busy &&
        (_text.text.trim().isNotEmpty || _photo != null || _song != null);
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        0,
        16,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_photo != null)
            Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: Image.memory(
                      _photo!,
                      fit: BoxFit.cover,
                      width: double.infinity,
                    ),
                  ),
                ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: IconButton.filledTonal(
                    tooltip: 'Remove photo',
                    onPressed: () => setState(() => _photo = null),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ],
            ),
          if (_photo != null) const SizedBox(height: 12),
          if (_song != null) ...[
            SongTile(
              song: _song!,
              onRemove: () => setState(() => _song = null),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _text,
            autofocus: _photo == null,
            minLines: 2,
            maxLines: 6,
            maxLength: AppConfig.maxTextLength,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: _photo == null && _song == null
                  ? 'What’s on your mind?'
                  : 'Add a caption (optional)',
              border: const OutlineInputBorder(),
            ),
          ),
          Row(
            children: [
              IconButton(
                tooltip: 'Add a photo',
                onPressed: _busy ? null : () => _pick(ImageSource.gallery),
                icon: const Icon(Icons.photo_outlined),
              ),
              IconButton(
                tooltip: 'Take a photo',
                onPressed: _busy ? null : () => _pick(ImageSource.camera),
                icon: const Icon(Icons.photo_camera_outlined),
              ),
              IconButton(
                tooltip: 'Add a Spotify song',
                onPressed: _busy ? null : _addSong,
                icon: const Icon(Icons.music_note_outlined),
              ),
              const Spacer(),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              FilledButton.icon(
                onPressed: canSend ? _send : null,
                icon: const Icon(Icons.send),
                label: Text(
                  widget.friendCount == 0
                      ? 'Share'
                      : 'Share with ${widget.friendCount}',
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Photos are resized and location data is removed before sharing.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
