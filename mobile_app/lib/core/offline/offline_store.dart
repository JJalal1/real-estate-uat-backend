import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

final offlineStoreProvider = Provider<OfflineStore>((ref) => OfflineStore());

/// Bounded app-private snapshots. Private payloads are sealed by Android Keystore;
/// there is deliberately no plaintext fallback when the native cipher is absent.
class OfflineStore {
  OfflineStore(
      {Future<Directory> Function()? directory,
      this.seal,
      this.open,
      DateTime Function()? clock,
      this.maxEntries = 240,
      this.maxBytes = 16 * 1024 * 1024})
      : _directory = directory,
        _clock = clock ?? DateTime.now;
  static const _channel = MethodChannel('real_estate/secure_store');
  final Future<Directory> Function()? _directory;
  final Future<String> Function(String)? seal, open;
  final DateTime Function() _clock;
  final int maxEntries, maxBytes;
  Future<void> _tail = Future.value();
  Future<void> get idle => _tail;
  Future<Directory> _root(String space) async {
    if (!RegExp(r'^[a-z_]+$').hasMatch(space)) {
      throw ArgumentError('Invalid offline space');
    }
    final support =
        await (_directory?.call() ?? getApplicationSupportDirectory());
    final base = _directory == null && Platform.isAndroid
        ? '${support.parent.path}/no_backup'
        : support.path;
    return Directory('$base/offline_v1/$space');
  }

  String _key(String value) {
    var a = 0x811c9dc5, b = 0x9e3779b9;
    for (final c in utf8.encode(value)) {
      a = ((a ^ c) * 0x01000193) & 0xffffffff;
      b = ((b ^ c) * 0x85ebca6b) & 0xffffffff;
    }
    return '${a.toRadixString(16).padLeft(8, '0')}${b.toRadixString(16).padLeft(8, '0')}';
  }

  Future<T> _serial<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<Map<String, dynamic>?> read(String space, String identity,
          {bool private = false, bool strict = false}) =>
      _serial(() async {
        try {
          final f = File('${(await _root(space)).path}/${_key(identity)}.json');
          if (!await f.exists()) {
            return null;
          }
          if (await f.length() > 2 * 1024 * 1024) {
            if (strict) {
              throw StateError('Invalid sealed state size');
            }
            return null;
          }
          var text = await f.readAsString();
          if (private) {
            text = await (open?.call(text) ??
                _channel.invokeMethod<String>(
                    'openOfflineState', {'value': text}).then((v) => v!));
          }
          final row = jsonDecode(text);
          if (row is! Map ||
              row['identity'] != identity ||
              row['data'] is! Map) {
            if (strict) throw StateError('Invalid sealed state');
            return null;
          }
          if (space != 'outbox' &&
              _clock().difference(DateTime.parse(row['at'] as String)) >
                  const Duration(days: 30)) {
            return null;
          }
          return Map<String, dynamic>.from(row['data'] as Map);
        } catch (_) {
          if (strict) rethrow;
          return null;
        }
      });
  Future<void> write(String space, String identity, Map<String, dynamic> data,
          {bool private = false, bool Function()? current}) =>
      _serial(() async {
        if (current?.call() == false) return;
        var text = jsonEncode({
          'identity': identity,
          'at': _clock().toIso8601String(),
          'data': data
        });
        if (utf8.encode(text).length > 768 * 1024) {
          throw StateError('Offline snapshot exceeds its bound');
        }
        if (private) {
          text = await (seal?.call(text) ??
              _channel.invokeMethod<String>(
                  'sealOfflineState', {'value': text}).then((v) => v!));
        }
        if (current?.call() == false) return;
        final root = await _root(space);
        await root.create(recursive: true);
        final target = File('${root.path}/${_key(identity)}.json');
        final staged = File('${target.path}.pending');
        await staged.writeAsString(text, flush: true);
        if (current?.call() == false) {
          await staged.delete();
          return;
        }
        await staged.rename(target.path);
        if (space != 'outbox') await _trim(root);
      });
  Future<void> forget(String space, String identity) => _serial(() async {
        final f = File('${(await _root(space)).path}/${_key(identity)}.json');
        if (await f.exists()) await f.delete();
      });
  Future<void> clear(String space) => _serial(() async {
        final d = await _root(space);
        if (await d.exists()) await d.delete(recursive: true);
      });
  Future<void> _trim(Directory root) async {
    final entries = <(File, DateTime, int)>[];
    await for (final f in root.list(followLinks: false)) {
      if (f is! File || !f.path.endsWith('.json')) continue;
      final stat = await f.stat();
      entries.add((f, stat.modified, stat.size));
    }
    entries.sort((a, b) => a.$2.compareTo(b.$2));
    var bytes = entries.fold<int>(0, (n, x) => n + x.$3),
        count = entries.length;
    for (final entry in entries) {
      if (count <= maxEntries && bytes <= maxBytes) break;
      await entry.$1.delete();
      count--;
      bytes -= entry.$3;
    }
  }
}
