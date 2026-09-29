import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/models.dart';
import '../data/repository.dart';
import 'common.dart';

class FriendsPage extends StatelessWidget {
  const FriendsPage({
    super.key,
    required this.repo,
    required this.profile,
    required this.friends,
    required this.requests,
  });

  final Repository repo;
  final Profile profile;
  final List<Person> friends;
  final List<Person> requests;

  Future<void> _add(BuildContext context) async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add a friend'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          decoration: const InputDecoration(
            labelText: 'Their friend code',
            hintText: 'ABCD2345',
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Send request'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
    if (code == null || code.trim().isEmpty || !context.mounted) return;
    try {
      final name = await repo.sendRequest(code);
      if (context.mounted) {
        toast(context, 'Request sent to $name. They need to approve it.');
      }
    } catch (e) {
      if (context.mounted) toast(context, errorText(e));
    }
  }

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
    String done,
  ) async {
    try {
      await action();
      if (context.mounted) toast(context, done);
    } catch (e) {
      if (context.mounted) toast(context, errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        Card(
          color: theme.colorScheme.secondaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Your friend code'),
                const SizedBox(height: 4),
                SelectableText(
                  profile.friendCode,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    letterSpacing: 4,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Give it only to people you want to hear from. You approve every request.',
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(
                        ClipboardData(text: profile.friendCode),
                      );
                      toast(context, 'Copied');
                    },
                    icon: const Icon(Icons.copy),
                    label: const Text('Copy'),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.tonalIcon(
          onPressed: () => _add(context),
          icon: const Icon(Icons.person_add_alt),
          label: const Text('Add a friend by code'),
        ),
        if (requests.isNotEmpty) ...[
          const SizedBox(height: 24),
          Text('Requests', style: theme.textTheme.titleMedium),
          for (final r in requests)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
              title: Text(r.displayName),
              subtitle: const Text('wants to share thoughts with you'),
              trailing: Wrap(
                children: [
                  IconButton(
                    tooltip: 'Decline',
                    onPressed: () =>
                        _run(context, () => repo.decline(r), 'Declined'),
                    icon: const Icon(Icons.close),
                  ),
                  IconButton.filled(
                    tooltip: 'Approve',
                    onPressed: () => _run(
                      context,
                      () => repo.accept(r),
                      'You and ${r.displayName} are friends',
                    ),
                    icon: const Icon(Icons.check),
                  ),
                ],
              ),
              onLongPress: () async {
                if (await confirm(
                  context,
                  title: 'Block ${r.displayName}?',
                  body: 'They won’t be able to send you requests.',
                  action: 'Block',
                  destructive: true,
                )) {
                  if (context.mounted) {
                    _run(context, () => repo.block(r.uid), 'Blocked');
                  }
                }
              },
            ),
        ],
        const SizedBox(height: 24),
        Text('Friends (${friends.length})', style: theme.textTheme.titleMedium),
        if (friends.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('No friends yet. Share your code, or add theirs.'),
          ),
        for (final f in friends)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              child: Text(
                f.displayName.isEmpty ? '?' : f.displayName.characters.first,
              ),
            ),
            title: Text(f.displayName),
            trailing: PopupMenuButton<String>(
              onSelected: (choice) async {
                final block = choice == 'block';
                final ok = await confirm(
                  context,
                  title: block
                      ? 'Block ${f.displayName}?'
                      : 'Remove ${f.displayName}?',
                  body: block
                      ? 'You’ll stop sharing thoughts, and they can’t send you requests again.'
                      : 'You’ll stop seeing each other’s thoughts. You can add each other again later.',
                  action: block ? 'Block' : 'Remove',
                  destructive: true,
                );
                if (!ok || !context.mounted) return;
                _run(
                  context,
                  () => block ? repo.block(f.uid) : repo.unfriend(f.uid),
                  block ? 'Blocked' : 'Removed',
                );
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'remove', child: Text('Remove friend')),
                PopupMenuItem(value: 'block', child: Text('Block')),
              ],
            ),
          ),
      ],
    );
  }
}
