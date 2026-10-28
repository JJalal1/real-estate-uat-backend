import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/network/api_client.dart';
import 'property_repository.dart';

class PublicPhotoRecord {
  const PublicPhotoRecord({required this.bytes, required this.etag, required this.expiresAt});
  final Uint8List bytes;
  final String etag;
  final DateTime expiresAt;
}

/// Only published API derivatives with an explicit public response contract.
/// Exact URL/variant/version identity is retained; signed and private URLs are
/// ineligible. Every process restart revalidates with ETag before accepting a
/// disk hit. IO is serialized, bounded and best effort, never a browsing gate.
class PublicPhotoDiskCache {
  PublicPhotoDiskCache({required this.origin, Future<Directory> Function()? directory,
    DateTime Function()? clock, this.maxEntries = 160, this.maxBytes = 48 * 1024 * 1024,
    this.maxImageBytes = 2 * 1024 * 1024})
    : _directory = directory ?? (() async => Directory('${(await getTemporaryDirectory()).path}/aqer-public-photos-v1')),
      _clock = clock ?? DateTime.now;
  final Uri origin;
  final Future<Directory> Function() _directory;
  final DateTime Function() _clock;
  final int maxEntries, maxBytes, maxImageBytes;
  Future<void> _tail = Future.value();
  int _epoch = 0;
  int get epoch => _epoch;
  Future<void> get idle => _tail;
  int hits = 0, writes = 0, invalidations = 0;

  bool eligible(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.userInfo.isNotEmpty || uri.hasFragment ||
        uri.host != origin.host || uri.port != origin.port ||
        !RegExp(r'^/api/property-media/[1-9][0-9]*$').hasMatch(uri.path) ||
        uri.queryParametersAll.values.any((values) => values.length != 1) ||
        uri.queryParameters.keys.any((key) => key != 'variant' && key != 'v')) { return false; }
    final variant = uri.queryParameters['variant'];
    final version = uri.queryParameters['v'];
    return (variant == null || const ['thumb','card','preview','detail','gallery'].contains(variant)) &&
      (version == null || RegExp(r'^[A-Za-z0-9_.-]{1,96}$').hasMatch(version));
  }

  // Hashes only bound file-name length. Exact URL equality in metadata is the
  // identity check, so a hash collision cannot return another image's bytes.
  String _key(String url) {
    var first = 0x811c9dc5, second = 0x9e3779b9;
    for (final unit in utf8.encode(url)) {
      first = ((first ^ unit) * 0x01000193) & 0xffffffff;
      second = ((second ^ unit) * 0x85ebca6b) & 0xffffffff;
    }
    return '${first.toRadixString(16).padLeft(8, '0')}${second.toRadixString(16).padLeft(8, '0')}';
  }

  Future<T?> _serial<T>(Future<T?> Function() action) {
    final result = Completer<T?>();
    _tail = _tail.then((_) async {
      try { result.complete(await action()); } catch (_) { result.complete(null); }
    });
    return result.future;
  }

  Future<PublicPhotoRecord?> read(String url) {
    if (!eligible(url)) return Future.value();
    final epoch = _epoch;
    return _serial(() async {
      if (epoch != _epoch) return null;
      final root = await _directory(), key = _key(url);
      final metadata = File('${root.path}/$key.json');
      final image = File('${root.path}/$key.img');
      if (!await metadata.exists() || !await image.exists()) return null;
      final raw = jsonDecode(await metadata.readAsString());
      if (raw is! Map || raw['url'] != url || raw['etag'] is! String ||
          raw['expires_at'] is! String) { return null; }
      final expires = DateTime.tryParse(raw['expires_at'] as String);
      final length = await image.length();
      if (expires == null || !expires.isAfter(_clock()) || length < 1 || length > maxImageBytes || raw['bytes'] != length) {
        await _remove(root, key); return null;
      }
      final bytes = await image.readAsBytes();
      if (epoch != _epoch) return null;
      hits++;
      return PublicPhotoRecord(bytes: bytes, etag: raw['etag'] as String, expiresAt: expires);
    });
  }

  Duration? _lifetime(Headers headers) {
    final rules = (headers.value('cache-control') ?? '').toLowerCase().split(',').map((v) => v.trim()).toSet();
    if (!rules.contains('public') || rules.contains('private') || rules.contains('no-store') ||
        rules.contains('no-cache') || headers['set-cookie']?.isNotEmpty == true ||
        !(headers.value('content-type') ?? '').toLowerCase().startsWith('image/') ||
        (headers.value('etag') ?? '').isEmpty) { return null; }
    for (final rule in rules) {
      if (!rule.startsWith('max-age=')) continue;
      final seconds = int.tryParse(rule.substring(8));
      if (seconds != null && seconds > 0) return Duration(seconds: seconds.clamp(1, 86400).toInt());
    }
    return null;
  }
  bool accepts(Headers headers) => _lifetime(headers) != null;

  Future<void> put(String url, Uint8List bytes, Headers headers, {required int expectedEpoch}) async {
    final lifetime = _lifetime(headers);
    if (!eligible(url) || lifetime == null || bytes.isEmpty || bytes.lengthInBytes > maxImageBytes) return;
    await _serial<void>(() async {
      if (_epoch != expectedEpoch) return;
      final root = await _directory(); await root.create(recursive: true);
      final key = _key(url), image = File('${root.path}/$key.img'), metadata = File('${root.path}/$key.json');
      final staged = File('${image.path}.tmp');
      await staged.writeAsBytes(bytes, flush: true);
      await staged.rename(image.path);
      final stagedMetadata = File('${metadata.path}.tmp');
      await stagedMetadata.writeAsString(jsonEncode({'url': url, 'etag': headers.value('etag'),
        'bytes': bytes.lengthInBytes, 'expires_at': _clock().add(lifetime).toIso8601String(),
        'stored_at': _clock().toIso8601String()}), flush: true);
      await stagedMetadata.rename(metadata.path);
      writes++;
      await _trim(root);
    });
  }

  Future<void> forget(String url) async {
    if (!eligible(url)) return;
    await _serial<void>(() async { await _remove(await _directory(), _key(url)); invalidations++; });
  }

  Future<void> clear() async {
    _epoch++;
    await _serial<void>(() async {
      final root = await _directory();
      if (await root.exists()) await root.delete(recursive: true);
      invalidations++;
    });
  }

  Future<void> _remove(Directory root, String key) async {
    for (final suffix in ['json', 'img', 'json.tmp', 'img.tmp']) {
      final file = File('${root.path}/$key.$suffix');
      if (await file.exists()) await file.delete();
    }
  }

  Future<void> _trim(Directory root) async {
    final entries = <({String key, DateTime at, int bytes})>[];
    await for (final file in root.list(followLinks: false)) {
      if (file is! File) continue;
      if (file.path.endsWith('.tmp') || (file.path.endsWith('.img') &&
          !await File(file.path.replaceFirst(RegExp(r'\.img$'), '.json')).exists())) {
        await file.delete(); continue;
      }
      if (!file.path.endsWith('.json')) continue;
      final key = file.uri.pathSegments.last.replaceAll('.json', '');
      try {
        final data = jsonDecode(await file.readAsString()) as Map;
        final expiry = DateTime.parse(data['expires_at'] as String);
        final image = File('${root.path}/$key.img');
        if (!expiry.isAfter(_clock()) || !await image.exists()) { await _remove(root, key); continue; }
        entries.add((key: key, at: DateTime.parse(data['stored_at'] as String), bytes: await image.length()));
      } catch (_) { await _remove(root, key); }
    }
    entries.sort((a, b) => a.at.compareTo(b.at));
    var count = entries.length, bytes = entries.fold<int>(0, (sum, entry) => sum + entry.bytes);
    for (final entry in entries) {
      if (count <= maxEntries && bytes <= maxBytes) break;
      await _remove(root, entry.key); count--; bytes -= entry.bytes;
    }
  }
}

final publicPhotoDiskCacheProvider = Provider<PublicPhotoDiskCache>((ref) {
  final cache = PublicPhotoDiskCache(origin: Uri.parse(ref.watch(dioProvider).options.baseUrl));
  ref.listen(propertyDataRevisionProvider, (_, __) { unawaited(cache.clear()); });
  return cache;
});
