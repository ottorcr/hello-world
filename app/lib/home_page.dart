import 'dart:async';
import 'dart:math';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'thought.dart';
import 'thought_repository.dart';
import 'widget_sync.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _repo = ThoughtRepository();
  final _random = Random();

  StreamSubscription<List<Thought>>? _thoughtsSub;
  StreamSubscription<User?>? _authSub;

  List<Thought>? _thoughts;
  Object? _error;
  Thought? _featured;
  User? _user;

  @override
  void initState() {
    super.initState();
    _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
      setState(() => _user = user);
    });
    _thoughtsSub = _repo.watchThoughts().listen((thoughts) {
      setState(() {
        _thoughts = thoughts;
        _error = null;
        if (_featured == null || !thoughts.any((t) => t.id == _featured!.id)) {
          _featured = _pickRandom(thoughts);
        }
      });
      WidgetSync.push(thoughts);
    }, onError: (Object e) => setState(() => _error = e));
  }

  @override
  void dispose() {
    _thoughtsSub?.cancel();
    _authSub?.cancel();
    super.dispose();
  }

  Thought? _pickRandom(List<Thought> thoughts, {Thought? avoid}) {
    if (thoughts.isEmpty) return null;
    if (thoughts.length == 1) return thoughts.first;
    Thought pick;
    do {
      pick = thoughts[_random.nextInt(thoughts.length)];
    } while (pick.id == avoid?.id);
    return pick;
  }

  void _shuffle() {
    final thoughts = _thoughts;
    if (thoughts == null) return;
    setState(() => _featured = _pickRandom(thoughts, avoid: _featured));
  }

  bool get _isAuthor => _user != null;

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _compose() async {
    final text = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _ComposeSheet(),
    );
    if (text == null || text.trim().isEmpty) return;
    try {
      await _repo.add(text);
      _toast('Sent to your friends’ home screens ✨');
    } on FirebaseException catch (e) {
      _toast(
        e.code == 'permission-denied'
            ? 'This account isn’t the author (check firestore.rules).'
            : 'Couldn’t post: ${e.message}',
      );
    }
  }

  Future<void> _delete(Thought thought) async {
    try {
      await _repo.delete(thought.id);
    } on FirebaseException catch (e) {
      _toast('Couldn’t delete: ${e.message}');
    }
  }

  Future<void> _toggleSignIn() async {
    if (_isAuthor) {
      await FirebaseAuth.instance.signOut();
      _toast('Signed out');
      return;
    }
    final signedIn = await showDialog<bool>(
      context: context,
      builder: (_) => const _SignInDialog(),
    );
    if (signedIn == true) _toast('Welcome back! Tap + to share a thought.');
  }

  @override
  Widget build(BuildContext context) {
    final thoughts = _thoughts;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Random Thoughts'),
        actions: [
          IconButton(
            tooltip: _isAuthor ? 'Sign out' : 'Author sign in',
            icon: Icon(_isAuthor ? Icons.logout : Icons.edit_note),
            onPressed: _toggleSignIn,
          ),
        ],
      ),
      floatingActionButton: _isAuthor
          ? FloatingActionButton.extended(
              onPressed: _compose,
              icon: const Icon(Icons.add),
              label: const Text('New thought'),
            )
          : null,
      body: _error != null
          ? _Message(
              icon: Icons.cloud_off,
              text: 'Couldn’t load thoughts.\n$_error',
            )
          : thoughts == null
          ? const Center(child: CircularProgressIndicator())
          : thoughts.isEmpty
          ? const _Message(
              icon: Icons.bubble_chart_outlined,
              text:
                  'No thoughts yet.\nThey’ll show up here and on your '
                  'home-screen widget.',
            )
          : _ThoughtsView(
              featured: _featured,
              thoughts: thoughts,
              canDelete: _isAuthor,
              onShuffle: _shuffle,
              onDelete: _delete,
            ),
    );
  }
}

class _ThoughtsView extends StatelessWidget {
  const _ThoughtsView({
    required this.featured,
    required this.thoughts,
    required this.canDelete,
    required this.onShuffle,
    required this.onDelete,
  });

  final Thought? featured;
  final List<Thought> thoughts;
  final bool canDelete;
  final VoidCallback onShuffle;
  final ValueChanged<Thought> onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        _FeaturedCard(thought: featured, onShuffle: onShuffle),
        const SizedBox(height: 12),
        Card.outlined(
          child: ListTile(
            leading: const Icon(Icons.widgets_outlined),
            title: const Text('Put this on your home screen'),
            subtitle: const Text(
              'Long-press your home screen → Widgets → Random Thoughts',
            ),
          ),
        ),
        const SizedBox(height: 24),
        Text('All thoughts', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final t in thoughts)
          canDelete
              ? Dismissible(
                  key: ValueKey(t.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    color: theme.colorScheme.errorContainer,
                    child: Icon(
                      Icons.delete,
                      color: theme.colorScheme.onErrorContainer,
                    ),
                  ),
                  confirmDismiss: (_) => showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Delete this thought?'),
                      content: Text(t.text),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Delete'),
                        ),
                      ],
                    ),
                  ),
                  onDismissed: (_) => onDelete(t),
                  child: _ThoughtTile(thought: t),
                )
              : _ThoughtTile(thought: t),
      ],
    );
  }
}

class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({required this.thought, required this.onShuffle});

  final Thought? thought;
  final VoidCallback onShuffle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.primaryContainer,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onShuffle,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('💭', style: Theme.of(context).textTheme.headlineMedium),
              const SizedBox(height: 12),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: Text(
                  thought?.text ?? '',
                  key: ValueKey(thought?.id),
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(color: scheme.onPrimaryContainer),
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onShuffle,
                  icon: const Icon(Icons.shuffle),
                  label: const Text('Another one'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThoughtTile extends StatelessWidget {
  const _ThoughtTile({required this.thought});

  final Thought thought;

  @override
  Widget build(BuildContext context) {
    final created = thought.createdAt;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(thought.text),
      subtitle: created == null ? null : Text(_timeAgo(created)),
    );
  }
}

String _timeAgo(DateTime time) {
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays < 30) return '${diff.inDays}d ago';
  return '${time.year}-${time.month.toString().padLeft(2, '0')}-'
      '${time.day.toString().padLeft(2, '0')}';
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48),
            const SizedBox(height: 16),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _ComposeSheet extends StatefulWidget {
  const _ComposeSheet();

  @override
  State<_ComposeSheet> createState() => _ComposeSheetState();
}

class _ComposeSheetState extends State<_ComposeSheet> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(context, _controller.text);

  @override
  Widget build(BuildContext context) {
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
          TextField(
            controller: _controller,
            autofocus: true,
            minLines: 3,
            maxLines: 6,
            maxLength: ThoughtRepository.maxThoughtLength,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              hintText: 'What’s on your mind?',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          ListenableBuilder(
            listenable: _controller,
            builder: (context, _) => FilledButton.icon(
              onPressed: _controller.text.trim().isEmpty ? null : _submit,
              icon: const Icon(Icons.send),
              label: const Text('Share'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SignInDialog extends StatefulWidget {
  const _SignInDialog();

  @override
  State<_SignInDialog> createState() => _SignInDialogState();
}

class _SignInDialogState extends State<_SignInDialog> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _email.text.trim(),
        password: _password.text,
      );
      if (mounted) Navigator.pop(context, true);
    } on FirebaseAuthException catch (e) {
      setState(() {
        _busy = false;
        _error = e.message ?? e.code;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Author sign in'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Only the author can post. Friends don’t need an account.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          TextField(
            controller: _password,
            obscureText: true,
            autofillHints: const [AutofillHints.password],
            decoration: InputDecoration(
              labelText: 'Password',
              errorText: _error,
            ),
            onSubmitted: (_) => _signIn(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _signIn,
          child: const Text('Sign in'),
        ),
      ],
    );
  }
}
