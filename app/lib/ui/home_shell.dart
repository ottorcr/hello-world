import 'dart:async';

import 'package:flutter/material.dart';

import '../data/models.dart';
import '../data/repository.dart';
import '../widget_sync.dart';
import 'compose_sheet.dart';
import 'feed_page.dart';
import 'friends_page.dart';
import 'me_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.repo, required this.profile});

  final Repository repo;
  final Profile profile;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;
  List<Post>? _inbox;
  List<Person>? _friendsLoaded;
  List<Person> get _friends => _friendsLoaded ?? const [];
  List<Person> _requests = const [];
  final _subs = <StreamSubscription<Object?>>[];

  @override
  void initState() {
    super.initState();
    final repo = widget.repo;
    _subs
      ..add(
        repo.watchFriends().listen((f) {
          _friendsLoaded = f;
          _publish();
        }),
      )
      ..add(
        repo.watchIncomingRequests().listen(
          (r) => setState(() => _requests = r),
        ),
      )
      ..add(
        repo.watchInbox().listen((posts) {
          _inbox = posts;
          _publish();
        }),
      );
  }

  /// Only show (and put on the widget) posts from people who are still
  /// friends. The rules already enforce this for new posts; this also hides
  /// older ones right away after an unfriend.
  void _publish() {
    final inbox = _inbox;
    if (inbox == null || _friendsLoaded == null) {
      setState(() {});
      return;
    }
    final friendIds = {for (final f in _friends) f.uid};
    final visible = inbox.where((p) => friendIds.contains(p.authorId)).toList();
    setState(() => _visible = visible);
    WidgetSync.push(visible, widget.repo);
  }

  List<Post>? _visible;

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  Future<void> _compose() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) =>
        ComposeSheet(repo: widget.repo, friendCount: _friends.length),
  );

  @override
  Widget build(BuildContext context) {
    final pages = [
      FeedPage(
        repo: widget.repo,
        posts: _visible,
        hasFriends: _friends.isNotEmpty,
        onAddFriends: () => setState(() => _tab = 1),
      ),
      FriendsPage(
        repo: widget.repo,
        profile: widget.profile,
        friends: _friends,
        requests: _requests,
      ),
      MePage(repo: widget.repo, profile: widget.profile),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text(const ['Random Thoughts', 'Friends', 'Me'][_tab]),
      ),
      body: pages[_tab],
      floatingActionButton: _tab == 0
          ? FloatingActionButton.extended(
              onPressed: _compose,
              icon: const Icon(Icons.add),
              label: const Text('New thought'),
            )
          : null,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.bubble_chart_outlined),
            label: 'Feed',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: _requests.isNotEmpty,
              label: Text('${_requests.length}'),
              child: const Icon(Icons.people_outline),
            ),
            label: 'Friends',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            label: 'Me',
          ),
        ],
      ),
    );
  }
}
