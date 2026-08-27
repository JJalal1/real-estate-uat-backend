import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

class Stage5DeviceStore {
  Stage5DeviceStore._();

  static final Stage5DeviceStore instance = Stage5DeviceStore._();

  static const _fileName = 'stage5_device_state.json';
  static const _ownerKeyField = 'owner_key';

  Future<void> _writeQueue = Future<void>.value();
  Future<String>? _ownerKeyOperation;

  Future<File> _file() async {
    final directory = await getApplicationSupportDirectory();
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return File('${directory.path}${Platform.pathSeparator}$_fileName');
  }

  Future<Map<String, dynamic>> _read() async {
    try {
      final file = await _file();
      if (!await file.exists()) return <String, dynamic>{};
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) return <String, dynamic>{};
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // A local cache problem must never prevent the application from opening.
    }
    return <String, dynamic>{};
  }

  Future<void> _write(Map<String, dynamic> state) {
    final operation = _writeQueue.then<void>(
      (_) async {
        final file = await _file();
        final temporary = File('${file.path}.tmp');
        await temporary.writeAsString(jsonEncode(state), flush: true);
        if (await file.exists()) {
          await file.delete();
        }
        await temporary.rename(file.path);
      },
      onError: (_, __) async {
        // A failed earlier write must not poison all later writes.
        final file = await _file();
        final temporary = File('${file.path}.tmp');
        await temporary.writeAsString(jsonEncode(state), flush: true);
        if (await file.exists()) await file.delete();
        await temporary.rename(file.path);
      },
    );

    _writeQueue = operation.then<void>((_) {}, onError: (_, __) {});
    return operation;
  }

  Future<String> ownerKey() {
    final running = _ownerKeyOperation;
    if (running != null) return running;

    final operation = _loadOrCreateOwnerKey();
    _ownerKeyOperation = operation;
    return operation.whenComplete(() {
      if (identical(_ownerKeyOperation, operation)) {
        _ownerKeyOperation = null;
      }
    });
  }

  Future<String> _loadOrCreateOwnerKey() async {
    final state = await _read();
    final existing = state[_ownerKeyField]?.toString().trim();
    if (existing != null && existing.length >= 32) return existing;

    final random = Random.secure();
    final bytes = List<int>.generate(32, (_) => random.nextInt(256));
    final key = base64UrlEncode(bytes).replaceAll('=', '');
    state[_ownerKeyField] = key;
    await _write(state);
    return key;
  }
}
