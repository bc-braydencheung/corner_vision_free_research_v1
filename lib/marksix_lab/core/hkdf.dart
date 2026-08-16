import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// HKDF-SHA256 (RFC 5869).
class Hkdf {
  static const int hashLen = 32;

  static Uint8List extract(List<int> salt, List<int> ikm) {
    final key = salt.isEmpty ? Uint8List(hashLen) : Uint8List.fromList(salt);
    return Uint8List.fromList(Hmac(sha256, key).convert(ikm).bytes);
  }

  static Uint8List expand(List<int> prk, List<int> info, int length) {
    if (length > 255 * hashLen) {
      throw ArgumentError('length exceeds 255 * HashLen');
    }
    final hmac = Hmac(sha256, prk);
    final out = Uint8List(length);
    var previous = <int>[];
    var offset = 0;
    var counter = 1;
    while (offset < length) {
      final block = hmac.convert(<int>[...previous, ...info, counter]).bytes;
      final take = (length - offset) < hashLen ? (length - offset) : hashLen;
      out.setRange(offset, offset + take, block);
      previous = block;
      offset += take;
      counter++;
    }
    return out;
  }

  static Uint8List derive({
    required List<int> ikm,
    List<int> salt = const <int>[],
    List<int> info = const <int>[],
    int length = 32,
  }) => expand(extract(salt, ikm), info, length);
}
