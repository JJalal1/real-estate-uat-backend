import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

final listingViewerKeyProvider = FutureProvider<String>((ref) => ListingViewerKeyStore.key());

class ListingViewerKeyStore {
  static Future<String>? _operation;
  static Future<String> key() {
    final inFlight = _operation;
    if (inFlight != null) return inFlight;
    final operation = _load();
    _operation = operation;
    // A temporary disk or plugin error must not permanently poison all
    // later calls to obtain a valid per-installation viewer identifier.
    operation.then<void>((_) {}, onError: (Object _, StackTrace __) {
      if (identical(_operation, operation)) _operation = null;
    });
    return operation;
  }
  static Future<String> _load() async {
    final root = await getApplicationSupportDirectory();
    await root.create(recursive: true);
    final file = File('${root.path}${Platform.pathSeparator}listing_viewer_key.txt');
    if (await file.exists()) {
      final current = (await file.readAsString()).trim();
      if (current.length >= 32 && current.length <= 128) return current;
    }
    final random = Random.secure();
    final key = base64UrlEncode(List<int>.generate(32, (_) => random.nextInt(256))).replaceAll('=', '');
    await file.writeAsString(key, flush: true);
    return key;
  }
}
