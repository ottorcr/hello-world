import 'package:flutter_test/flutter_test.dart';
import 'package:random_thoughts/firebase_options.dart';

void main() {
  test('placeholder Firebase options are present until flutterfire runs', () {
    expect(DefaultFirebaseOptions.android.projectId, isNotEmpty);
  });
}
