import 'package:cloud_firestore/cloud_firestore.dart';

DateTime? _date(Object? v) => v is Timestamp ? v.toDate() : null;

class Profile {
  const Profile({required this.displayName, required this.friendCode});

  final String displayName;
  final String friendCode;

  static Profile? fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    if (d == null) return null;
    return Profile(
      displayName: d['displayName'] as String? ?? '',
      friendCode: d['friendCode'] as String? ?? '',
    );
  }
}

/// A thought a friend sent to me (users/{me}/inbox/{id}).
class Post {
  const Post({
    required this.id,
    required this.authorId,
    required this.authorName,
    required this.text,
    required this.hasImage,
    this.createdAt,
  });

  final String id;
  final String authorId;
  final String authorName;
  final String text;
  final bool hasImage;
  final DateTime? createdAt;

  factory Post.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return Post(
      id: doc.id,
      authorId: d['authorId'] as String? ?? '',
      authorName: d['authorName'] as String? ?? '',
      text: d['text'] as String? ?? '',
      hasImage: d['hasImage'] as bool? ?? false,
      createdAt: _date(d['createdAt']),
    );
  }
}

/// A thought I sent (users/{me}/sent/{id}).
class SentPost {
  const SentPost({
    required this.id,
    required this.text,
    required this.hasImage,
    required this.recipients,
    this.createdAt,
  });

  final String id;
  final String text;
  final bool hasImage;
  final List<String> recipients;
  final DateTime? createdAt;

  factory SentPost.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? const {};
    return SentPost(
      id: doc.id,
      text: d['text'] as String? ?? '',
      hasImage: d['hasImage'] as bool? ?? false,
      recipients: List<String>.from(d['recipients'] as List? ?? const []),
      createdAt: _date(d['createdAt']),
    );
  }
}

/// A friend, or a pending friend request.
class Person {
  const Person({required this.uid, required this.displayName});

  final String uid;
  final String displayName;

  factory Person.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) => Person(
    uid: doc.id,
    displayName: doc.data()?['displayName'] as String? ?? '',
  );
}
