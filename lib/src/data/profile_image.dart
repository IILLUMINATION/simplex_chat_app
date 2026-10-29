import 'dart:convert';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// The core rejects profile images whose data URL is longer than this
/// (`maxProfileImageSize` in SimpleX `Library/Commands.hs`). The official
/// clients crop to a square and shrink until the encoded string fits.
const int maxProfileImageDataSize = 12500;

const String _jpegPrefix = 'data:image/jpeg;base64,';

/// Centre-crops [bytes] to a square and shrinks it until the data URL fits the
/// core cap, mirroring `cropToSquare` + `resizeImageToStrSize(…, 12500)` in
/// the official client's profile editor.
String? profileImageDataUri(Uint8List bytes) {
  final img.Image? decoded;
  try {
    decoded = img.decodeImage(bytes);
  } catch (_) {
    // Decoders for exotic formats can throw on hostile input; a picked file is
    // untrusted, so treat that as "not an image".
    return null;
  }
  if (decoded == null) return null;
  final side = decoded.width < decoded.height ? decoded.width : decoded.height;
  final square = img.copyCrop(
    decoded,
    x: (decoded.width - side) ~/ 2,
    y: (decoded.height - side) ~/ 2,
    width: side,
    height: side,
  );
  for (var target = 256; target >= 64; target ~/= 2) {
    final resized = target < side
        ? img.copyResize(square, width: target, height: target)
        : square;
    for (final quality in const [85, 75, 60, 45]) {
      final jpg = img.encodeJpg(resized, quality: quality);
      final uri = '$_jpegPrefix${base64Encode(jpg)}';
      if (uri.length <= maxProfileImageDataSize) return uri;
    }
  }
  return null;
}

/// Decodes a profile `image` field (a `data:` URL) into raw bytes.
Uint8List? profileImageBytes(String? dataUri) {
  if (dataUri == null || dataUri.isEmpty) return null;
  final marker = 'base64,';
  final index = dataUri.indexOf(marker);
  if (index == -1) return null;
  try {
    return base64Decode(dataUri.substring(index + marker.length));
  } catch (_) {
    return null;
  }
}
