import 'package:cloud_firestore/cloud_firestore.dart';

import 'thought.dart';

/// Reads and writes thoughts in Firestore.
///
/// Anyone can read (friends and their widgets); only the author can write.
/// Both rules are enforced in `firestore.rules`.
class ThoughtRepository {
  ThoughtRepository([FirebaseFirestore? firestore])
    : _col = (firestore ?? FirebaseFirestore.instance).collection('thoughts');

  static const maxThoughtLength = 280;

  final CollectionReference<Map<String, dynamic>> _col;

  Stream<List<Thought>> watchThoughts() => _col
      .orderBy('createdAt', descending: true)
      .limit(200)
      .snapshots()
      .map((snap) => snap.docs.map(Thought.fromDoc).toList());

  Future<void> add(String text) => _col.add({
    'text': text.trim(),
    'createdAt': FieldValue.serverTimestamp(),
  });

  Future<void> delete(String id) => _col.doc(id).delete();
}
