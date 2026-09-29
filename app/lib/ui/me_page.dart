import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../data/models.dart';
import '../data/repository.dart';
import '../widget_sync.dart';
import 'common.dart';
import 'feed_page.dart';

class MePage extends StatelessWidget {
  const MePage({super.key, required this.repo, required this.profile});

  final Repository repo;
  final Profile profile;

  Future<void> _rename(BuildContext context) async {
    final controller = TextEditingController(text: profile.displayName);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Your name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: AppConfig.maxNameLength,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
    if (name == null) return;
    try {
      await repo.rename(name);
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
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(profile.displayName, style: theme.textTheme.titleLarge),
          subtitle: Text(FirebaseAuth.instance.currentUser?.email ?? ''),
          trailing: IconButton(
            onPressed: () => _rename(context),
            icon: const Icon(Icons.edit_outlined),
          ),
        ),
        const SizedBox(height: 16),
        Text('Thoughts you shared', style: theme.textTheme.titleMedium),
        StreamBuilder<List<SentPost>>(
          stream: repo.watchSent(),
          builder: (context, snap) {
            final sent = snap.data;
            if (sent == null) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: LinearProgressIndicator(),
              );
            }
            if (sent.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Nothing yet.'),
              );
            }
            return Column(
              children: [
                for (final s in sent)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: s.hasImage
                        ? SizedBox.square(
                            dimension: 48,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: PostImage(repo: repo, postId: s.id),
                            ),
                          )
                        : null,
                    title: Text(
                      s.text.isEmpty ? '📷 Photo' : s.text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${timeAgo(s.createdAt)} · ${s.recipients.length} friends',
                    ),
                    trailing: IconButton(
                      tooltip: 'Unsend',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () async {
                        if (!await confirm(
                          context,
                          title: 'Unsend this thought?',
                          body: 'It will be removed from all your friends’ feeds and widgets.',
                          action: 'Unsend',
                          destructive: true,
                        )) {
                          return;
                        }
                        try {
                          await repo.unsend(s);
                        } catch (e) {
                          if (context.mounted) toast(context, errorText(e));
                        }
                      },
                    ),
                  ),
              ],
            );
          },
        ),
        const Divider(height: 32),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.privacy_tip_outlined),
          title: const Text('Privacy policy'),
          onTap: () => launchUrl(Uri.parse(AppConfig.privacyPolicyUrl)),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.logout),
          title: const Text('Sign out'),
          onTap: () => FirebaseAuth.instance.signOut(),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(
            Icons.delete_forever_outlined,
            color: theme.colorScheme.error,
          ),
          title: Text(
            'Delete account',
            style: TextStyle(color: theme.colorScheme.error),
          ),
          subtitle: const Text(
            'Removes your account, friends, and everything you shared',
          ),
          onTap: () => _deleteAccount(context),
        ),
      ],
    );
  }

  Future<void> _deleteAccount(BuildContext context) async {
    final password = await _askPassword(context);
    if (password == null || !context.mounted) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final progress = showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 16),
            Text('Deleting…'),
          ],
        ),
      ),
    );
    try {
      // Firebase only lets recently signed-in users delete their account.
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: user.email!, password: password),
      );
      await repo.deleteAllData();
      await WidgetSync.clear();
      await user.delete();
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        toast(
          context,
          e is FirebaseAuthException ? 'Wrong password.' : errorText(e),
        );
      }
      return;
    }
    await progress;
  }

  Future<String?> _askPassword(BuildContext context) {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete your account?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'This permanently deletes your account, your friend list, and every '
              'thought and photo you shared, including the copies your friends have. '
              'It can’t be undone.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password to confirm',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Delete forever'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }
}
