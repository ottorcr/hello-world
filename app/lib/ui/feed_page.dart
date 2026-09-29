import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import 'common.dart';
import 'song_widgets.dart';

class FeedPage extends StatefulWidget {
  const FeedPage({
    super.key,
    required this.repo,
    required this.posts,
    required this.hasFriends,
    required this.onAddFriends,
  });

  final Repository repo;
  final List<Post>? posts;
  final bool hasFriends;
  final VoidCallback onAddFriends;

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  final _random = Random();
  String? _featuredId;

  Post? get _featured {
    final posts = widget.posts;
    if (posts == null || posts.isEmpty) return null;
    return posts.firstWhere(
      (p) => p.id == _featuredId,
      orElse: () {
        final pick = posts[_random.nextInt(posts.length)];
        _featuredId = pick.id;
        return pick;
      },
    );
  }

  void _shuffle() {
    final posts = widget.posts;
    if (posts == null || posts.length < 2) return;
    String next;
    do {
      next = posts[_random.nextInt(posts.length)].id;
    } while (next == _featuredId);
    setState(() => _featuredId = next);
  }

  @override
  Widget build(BuildContext context) {
    final posts = widget.posts;
    if (posts == null) return const Center(child: CircularProgressIndicator());
    if (posts.isEmpty) {
      return MessageView(
        icon: Icons.bubble_chart_outlined,
        text: widget.hasFriends
            ? 'No thoughts yet.\nWhen a friend shares one, it shows up here and on your widget.'
            : 'Add a friend to start seeing their thoughts.',
        action: widget.hasFriends
            ? null
            : FilledButton.tonal(
                onPressed: widget.onAddFriends,
                child: const Text('Add friends'),
              ),
      );
    }
    final featured = _featured!;
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        PostCard(
          post: featured,
          repo: widget.repo,
          featured: true,
          onShuffle: _shuffle,
        ),
        const SizedBox(height: 12),
        const Card.outlined(
          child: ListTile(
            leading: Icon(Icons.widgets_outlined),
            title: Text('Put this on your home screen'),
            subtitle: Text(
              'Long-press your home screen → Widgets → Random Thoughts',
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('Everything', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final p in posts)
          if (p.id != featured.id) PostCard(post: p, repo: widget.repo),
      ],
    );
  }
}

class PostCard extends StatelessWidget {
  const PostCard({
    super.key,
    required this.post,
    required this.repo,
    this.featured = false,
    this.onShuffle,
  });

  final Post post;
  final Repository repo;
  final bool featured;
  final VoidCallback? onShuffle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      color: featured ? scheme.primaryContainer : null,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            leading: CircleAvatar(child: Text(_initial(post.authorName))),
            title: Text(post.authorName),
            subtitle: Text(timeAgo(post.createdAt)),
            trailing: _PostMenu(post: post, repo: repo),
          ),
          if (post.hasImage) PostImage(repo: repo, postId: post.id),
          if (post.song != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: SongTile(song: post.song!),
            ),
          if (post.text.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Text(
                post.text,
                style: featured
                    ? theme.textTheme.headlineSmall
                    : theme.textTheme.bodyLarge,
              ),
            ),
          if (onShuffle != null)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 8, bottom: 8),
                child: TextButton.icon(
                  onPressed: onShuffle,
                  icon: const Icon(Icons.shuffle),
                  label: const Text('Another one'),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _initial(String name) =>
      name.isEmpty ? '?' : String.fromCharCode(name.runes.first).toUpperCase();
}

class PostImage extends StatefulWidget {
  const PostImage({super.key, required this.repo, required this.postId});

  final Repository repo;
  final String postId;

  @override
  State<PostImage> createState() => _PostImageState();
}

class _PostImageState extends State<PostImage> {
  late Future<Uint8List?> _bytes = widget.repo.image(widget.postId);

  @override
  void didUpdateWidget(PostImage old) {
    super.didUpdateWidget(old);
    if (old.postId != widget.postId) _bytes = widget.repo.image(widget.postId);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _bytes,
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null) {
          return AspectRatio(
            aspectRatio: 4 / 3,
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: snap.connectionState == ConnectionState.done
                  ? const Icon(Icons.broken_image_outlined)
                  : const Center(child: CircularProgressIndicator()),
            ),
          );
        }
        return Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true);
      },
    );
  }
}

enum _Action { hide, report, block }

class _PostMenu extends StatelessWidget {
  const _PostMenu({required this.post, required this.repo});

  final Post post;
  final Repository repo;

  Future<void> _run(BuildContext context, _Action action) async {
    try {
      switch (action) {
        case _Action.hide:
          await repo.hide(post);
        case _Action.report:
          final reason = await _askReason(context);
          if (reason == null) return;
          await repo.report(post, reason);
          if (context.mounted) {
            toast(
              context,
              'Thanks. We’ll review it. You can also block ${post.authorName}.',
            );
          }
        case _Action.block:
          final ok = await confirm(
            context,
            title: 'Block ${post.authorName}?',
            body:
                'You’ll stop being friends, their thoughts disappear, '
                'and they can’t send you friend requests.',
            action: 'Block',
            destructive: true,
          );
          if (!ok) return;
          await repo.block(post.authorId);
      }
    } catch (e) {
      if (context.mounted) toast(context, errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_Action>(
      onSelected: (a) => _run(context, a),
      itemBuilder: (_) => const [
        PopupMenuItem(value: _Action.hide, child: Text('Hide')),
        PopupMenuItem(value: _Action.report, child: Text('Report')),
        PopupMenuItem(value: _Action.block, child: Text('Block')),
      ],
    );
  }
}

Future<String?> _askReason(BuildContext context) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Report this thought'),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: 500,
        maxLines: 3,
        decoration: const InputDecoration(hintText: 'What’s wrong with it?'),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            ctx,
            controller.text.trim().isEmpty ? 'unspecified' : controller.text,
          ),
          child: const Text('Report'),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}
