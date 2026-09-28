import 'package:cloud_firestore/cloud_firestore.dart';

/// One random thought, stored in the `thoughts` Firestore collection.
class Thought {
  const Thought({required this.id, required this.text, this.createdAt});

  final String id;
  final String text;
  final DateTime? createdAt;

  factory Thought.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    final ts = data['createdAt'];
    return Thought(
      id: doc.id,
      text: (data['text'] as String?) ?? '',
      createdAt: ts is Timestamp ? ts.toDate() : null,
    );
  }
}
