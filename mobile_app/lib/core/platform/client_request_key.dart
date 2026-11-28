import 'dart:math';

String newClientRequestKey() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final key =
      bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
  return '${key.substring(0, 8)}-${key.substring(8, 12)}-'
      '${key.substring(12, 16)}-${key.substring(16, 20)}-${key.substring(20)}';
}
