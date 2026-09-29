import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:random_thoughts/config.dart';
import 'package:random_thoughts/data/image_prep.dart';

void main() {
  test('removes EXIF (including GPS) and resizes large photos', () {
    final original = img.Image(width: 3000, height: 2000);
    img.fill(original, color: img.ColorRgb8(200, 120, 40));
    original.exif.gpsIfd['GPSLatitude'] = img.IfdValueRational(14, 1);
    original.exif.imageIfd['Make'] = img.IfdValueAscii('SecretPhone');
    final withExif = img.encodeJpg(original);
    expect(
      img.decodeJpg(withExif)!.exif.isEmpty,
      isFalse,
      reason: 'fixture should carry EXIF',
    );

    final prepared = prepareSync(withExif)!;
    final decoded = img.decodeJpg(prepared)!;

    expect(decoded.exif.isEmpty, isTrue);
    expect(String.fromCharCodes(prepared).contains('SecretPhone'), isFalse);
    expect(decoded.width, 1280);
    expect(decoded.height, 853);
    expect(prepared.length, lessThanOrEqualTo(AppConfig.maxImageBytes));
  });

  test('rotates according to EXIF orientation before stripping it', () {
    final original = img.Image(width: 400, height: 200);
    original.exif.imageIfd.orientation = 6; // rotate 90° clockwise
    final prepared = prepareSync(img.encodeJpg(original))!;
    final decoded = img.decodeJpg(prepared)!;
    expect(decoded.width, 200);
    expect(decoded.height, 400);
  });

  test('rejects data that is not an image', () {
    expect(prepareSync(Uint8List.fromList([1, 2, 3, 4])), isNull);
  });
}
