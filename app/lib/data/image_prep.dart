import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

import '../config.dart';
import 'repository.dart';

/// Turns a picked photo into a small JPEG that is safe to share. It is
/// rotated upright, resized to at most 1280 px, and stripped of all metadata
/// (EXIF, including GPS location).
Future<Uint8List> preparePhoto(Uint8List original) async {
  final result = await compute(_prepare, original);
  if (result == null) {
    throw const UserFacingException(
      'Couldn’t read that photo. Try a JPEG or PNG.',
    );
  }
  return result;
}

@visibleForTesting
Uint8List? prepareSync(Uint8List original) => _prepare(original);

Uint8List? _prepare(Uint8List original) {
  img.Image? decoded;
  try {
    decoded = img.decodeImage(original);
  } catch (_) {
    // Corrupt or unsupported files can make decoders throw.
  }
  if (decoded == null) return null;

  var image = img.bakeOrientation(decoded);
  const maxSide = 1280;
  final longest = max(image.width, image.height);
  if (longest > maxSide) {
    image = image.width >= image.height
        ? img.copyResize(image, width: maxSide)
        : img.copyResize(image, height: maxSide);
  }
  image.exif = img.ExifData();

  for (final quality in const [82, 72, 62, 50, 40]) {
    final jpeg = img.encodeJpg(image, quality: quality);
    if (jpeg.length <= AppConfig.maxImageBytes) return jpeg;
  }
  return null;
}
