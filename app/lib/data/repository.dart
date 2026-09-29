import 'dart:math';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../config.dart';
import 'models.dart';
import 'spotify.dart';

/// Thrown for problems the user can fix, with a message to show them.
class UserFacingException implements Exception {
  const UserFacingException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// All Firestore access for the signed-in user [uid].
///
/// The security rules in `firestore.rules` enforce who may read or write
/// what. This class only makes the calls the rules allow.
class Repository {
  Repository(this.uid, [FirebaseFirestore? firestore])
    : _db = firestore ?? FirebaseFirestore.instance;

  final String uid;
  final FirebaseFirestore _db;

  DocumentReference<Map<String, dynamic>> _user(String id) =>
      _db.doc('users/$id');
  CollectionReference<Map<String, dynamic>> _sub(String id, String name) =>
      _user(id).collection(name);

  // ---------------------------------------------------------------- profile

  Stream<Profile?> watchProfile() =>
      _user(uid).snapshots().map(Profile.fromDoc);

  Future<Profile?> getProfile() async =>
      Profile.fromDoc(await _user(uid).get());

  /// Creates the profile and claims a unique friend code.
  Future<void> createProfile(String displayName) async {
    final name = _cleanName(displayName);
    for (var attempt = 0; attempt < 5; attempt++) {
      final code = _randomCode();
      final codeRef = _db.doc('friendCodes/$code');
      final claimed = await _db.runTransaction((tx) async {
        if ((await tx.get(codeRef)).exists) return false;
        tx.set(codeRef, {'uid': uid, 'displayName': name});
        tx.set(_user(uid), {
          'displayName': name,
          'friendCode': code,
          'createdAt': FieldValue.serverTimestamp(),
        });
        return true;
      });
      if (claimed) return;
    }
    throw const UserFacingException(
      'Couldn’t create a friend code. Try again.',
    );
  }

  Future<void> rename(String displayName) async {
    final profile = await getProfile();
    if (profile == null) return;
    final name = _cleanName(displayName);
    final batch = _db.batch()
      ..update(_user(uid), {'displayName': name})
      ..update(_db.doc('friendCodes/${profile.friendCode}'), {
        'uid': uid,
        'displayName': name,
      });
    await batch.commit();
  }

  // -------------------------------------------------------- friend requests

  Stream<List<Person>> watchIncomingRequests() => _sub(
    uid,
    'requests',
  ).snapshots().map((s) => s.docs.map(Person.fromDoc).toList());

  /// Sends a friend request to whoever owns [rawCode]. If they already asked
  /// to be my friend, accepts instead. Returns their display name.
  Future<String> sendRequest(String rawCode) async {
    final code = rawCode.trim().toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
    if (!RegExp(r'^[A-Z2-9]{8}$').hasMatch(code)) {
      throw const UserFacingException(
        'Friend codes are 8 letters and numbers.',
      );
    }
    final codeDoc = await _db.doc('friendCodes/$code').get();
    final otherUid = codeDoc.data()?['uid'] as String?;
    final otherName =
        codeDoc.data()?['displayName'] as String? ?? 'your friend';
    if (otherUid == null) {
      throw const UserFacingException('No one has that friend code.');
    }
    if (otherUid == uid) {
      throw const UserFacingException('That’s your own code 🙂');
    }
    if ((await _sub(uid, 'friends').doc(otherUid).get()).exists) {
      throw UserFacingException('You and $otherName are already friends.');
    }
    final theirRequest = await _sub(uid, 'requests').doc(otherUid).get();
    if (theirRequest.exists) {
      await accept(Person.fromDoc(theirRequest));
      return otherName;
    }
    final me = await getProfile();
    final batch = _db.batch()
      ..set(_sub(otherUid, 'requests').doc(uid), {
        'displayName': me?.displayName ?? 'Someone',
        'createdAt': FieldValue.serverTimestamp(),
      })
      ..set(_sub(uid, 'outgoing').doc(otherUid), {
        'createdAt': FieldValue.serverTimestamp(),
      });
    try {
      await batch.commit();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw const UserFacingException(
          'Couldn’t send a request to that code.',
        );
      }
      rethrow;
    }
    return otherName;
  }

  Future<void> accept(Person requester) async {
    final me = await getProfile();
    final batch = _db.batch()
      ..set(_sub(uid, 'friends').doc(requester.uid), {
        'displayName': requester.displayName,
        'since': FieldValue.serverTimestamp(),
      })
      ..set(_sub(requester.uid, 'friends').doc(uid), {
        'displayName': me?.displayName ?? 'Friend',
        'since': FieldValue.serverTimestamp(),
      })
      ..delete(_sub(uid, 'requests').doc(requester.uid));
    await batch.commit();
  }

  Future<void> decline(Person requester) =>
      _sub(uid, 'requests').doc(requester.uid).delete();

  // ---------------------------------------------------------------- friends

  Stream<List<Person>> watchFriends() => _sub(uid, 'friends')
      .orderBy('displayName')
      .snapshots()
      .map((s) => s.docs.map(Person.fromDoc).toList());

  Future<List<String>> _friendIds() async =>
      (await _sub(uid, 'friends').get()).docs.map((d) => d.id).toList();

  /// Ends the friendship on both sides, and removes each person's posts from
  /// the other's inbox.
  Future<void> unfriend(String friendUid) async {
    final theirPostsToMe = await _sub(
      uid,
      'inbox',
    ).where('authorId', isEqualTo: friendUid).get();
    final myPostsToThem = await _sub(
      friendUid,
      'inbox',
    ).where('authorId', isEqualTo: uid).get();
    await _commitDeletes([
      _sub(uid, 'friends').doc(friendUid),
      _sub(friendUid, 'friends').doc(uid),
      // Clear leftover requests in both directions.
      _sub(uid, 'requests').doc(friendUid),
      _sub(friendUid, 'requests').doc(uid),
      _sub(uid, 'outgoing').doc(friendUid),
      for (final d in theirPostsToMe.docs) d.reference,
      for (final d in myPostsToThem.docs) d.reference,
    ]);
  }

  /// Unfriends and stops [otherUid] from sending new friend requests.
  Future<void> block(String otherUid) async {
    await unfriend(otherUid);
    final batch = _db.batch()
      ..set(_sub(uid, 'blocked').doc(otherUid), {
        'createdAt': FieldValue.serverTimestamp(),
      });
    await batch.commit();
  }

  Future<void> report(Post post, String reason) =>
      _db.collection('reports').add({
        'reporterId': uid,
        'reportedUid': post.authorId,
        'postId': post.id,
        'text': post.text,
        'reason': _clip(reason.trim(), 500),
        'createdAt': FieldValue.serverTimestamp(),
      });

  // ------------------------------------------------------------------ posts

  Stream<List<Post>> watchInbox() => _sub(uid, 'inbox')
      .orderBy('createdAt', descending: true)
      .limit(100)
      .snapshots()
      .map((s) => s.docs.map(Post.fromDoc).toList());

  Future<List<Post>> fetchInbox() async =>
      (await _sub(
            uid,
            'inbox',
          ).orderBy('createdAt', descending: true).limit(100).get()).docs
          .map(Post.fromDoc)
          .toList();

  Stream<List<SentPost>> watchSent() => _sub(uid, 'sent')
      .orderBy('createdAt', descending: true)
      .limit(100)
      .snapshots()
      .map((s) => s.docs.map(SentPost.fromDoc).toList());

  /// Sends a thought (with an optional JPEG photo and/or Spotify song) to all
  /// current friends. Returns how many friends received it.
  Future<int> send({required String text, Uint8List? jpeg, Song? song}) async {
    final body = text.trim();
    if (body.isEmpty && jpeg == null && song == null) {
      throw const UserFacingException(
        'Write something, or add a photo or song.',
      );
    }
    // The rules count Unicode code points, so count runes rather than UTF-16.
    if (body.runes.length > AppConfig.maxTextLength) {
      throw const UserFacingException('That’s a bit long. Keep it to 280.');
    }
    if (jpeg != null && jpeg.length > AppConfig.maxImageBytes) {
      throw const UserFacingException('That photo is too large.');
    }
    final friends = await _friendIds();
    if (friends.isEmpty) {
      throw const UserFacingException('Add a friend first. Share your code!');
    }
    if (friends.length > AppConfig.maxRecipients) {
      throw const UserFacingException('Too many friends to send to at once.');
    }
    final me = await getProfile();
    final sentRef = _sub(uid, 'sent').doc();
    final batch = _db.batch();
    if (jpeg != null) {
      batch.set(_db.doc('images/${sentRef.id}'), {
        'authorId': uid,
        'data': Blob(jpeg),
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    batch.set(sentRef, {
      'text': body,
      'hasImage': jpeg != null,
      if (song != null) 'song': song.toMap(),
      'recipients': friends,
      'createdAt': FieldValue.serverTimestamp(),
    });
    for (final friend in friends) {
      batch.set(_sub(friend, 'inbox').doc(sentRef.id), {
        'authorId': uid,
        'authorName': me?.displayName ?? 'Friend',
        'text': body,
        'hasImage': jpeg != null,
        if (song != null) 'song': song.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
    try {
      await batch.commit();
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw const UserFacingException(
          'Your friend list changed while sending. Try again.',
        );
      }
      rethrow;
    }
    return friends.length;
  }

  /// Deletes a thought I sent, including every friend's copy and the photo.
  Future<void> unsend(SentPost post) => _commitDeletes([
    for (final r in post.recipients) _sub(r, 'inbox').doc(post.id),
    if (post.hasImage) _db.doc('images/${post.id}'),
    _sub(uid, 'sent').doc(post.id),
  ]);

  /// Removes a thought from my own inbox.
  Future<void> hide(Post post) => _sub(uid, 'inbox').doc(post.id).delete();

  final _imageCache = <String, Uint8List?>{};

  /// The photo for a post in my inbox (or one I sent), or null.
  Future<Uint8List?> image(String postId) async {
    if (_imageCache.containsKey(postId)) return _imageCache[postId];
    try {
      final doc = await _db.doc('images/$postId').get();
      final bytes = (doc.data()?['data'] as Blob?)?.bytes;
      return _imageCache[postId] = bytes;
    } on FirebaseException {
      return null; // Unsent, or no longer friends.
    }
  }

  // --------------------------------------------------------- account delete

  /// Deletes everything this user created or received. Call it right before
  /// deleting the Firebase Auth user.
  Future<void> deleteAllData() async {
    for (final doc in (await _sub(uid, 'sent').get()).docs) {
      await unsend(SentPost.fromDoc(doc));
    }
    for (final friend in await _friendIds()) {
      await unfriend(friend);
    }
    final outgoing = (await _sub(uid, 'outgoing').get()).docs;
    final profile = await getProfile();
    await _commitDeletes([
      for (final d in outgoing) _sub(d.id, 'requests').doc(uid),
      for (final d in outgoing) d.reference,
      for (final name in const ['inbox', 'requests', 'blocked'])
        for (final d in (await _sub(uid, name).get()).docs) d.reference,
      if (profile != null) _db.doc('friendCodes/${profile.friendCode}'),
      _user(uid),
    ]);
  }

  // ---------------------------------------------------------------- helpers

  Future<void> _commitDeletes(List<DocumentReference> refs) async {
    for (var i = 0; i < refs.length; i += 450) {
      final batch = _db.batch();
      for (final ref in refs.skip(i).take(450)) {
        batch.delete(ref);
      }
      await batch.commit();
    }
  }

  static String _cleanName(String name) {
    final trimmed = name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (trimmed.isEmpty) throw const UserFacingException('Pick a name.');
    return _clip(trimmed, AppConfig.maxNameLength);
  }

  /// Shortens [s] to at most [max] code points without splitting emoji.
  static String _clip(String s, int max) =>
      s.runes.length <= max ? s : String.fromCharCodes(s.runes.take(max));

  static const _alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  static String _randomCode() {
    final rng = Random.secure();
    return List.generate(
      8,
      (_) => _alphabet[rng.nextInt(_alphabet.length)],
    ).join();
  }
}
