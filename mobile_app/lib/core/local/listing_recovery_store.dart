import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

final listingRecoveryStoreProvider = Provider<ListingRecoveryStore>((ref) => ListingRecoveryStore());

/// Private device recovery, separate from an explicitly saved server draft.
class ListingRecoveryStore {
  ListingRecoveryStore({Future<Directory> Function()? directory}) : _directory = directory;
  final Future<Directory> Function()? _directory;
  Future<void> _queue = Future<void>.value();

  Future<Directory> _scope(int userId, int? listingId) async {
    if (userId <= 0 || (listingId != null && listingId <= 0)) throw ArgumentError('Invalid recovery scope');
    final support = await (_directory?.call() ?? getApplicationSupportDirectory());
    // Android's app-private no_backup folder keeps location/contact data out of OS cloud backups.
    final base = _directory == null && Platform.isAndroid ? Directory('${support.parent.path}/no_backup') : support;
    return Directory('${base.path}/listing_recovery/u$userId/p${listingId ?? 0}');
  }

  static bool isSavedMedia(String path) => path.replaceAll('\\', '/').contains('/listing_recovery/');

  static final _key = RegExp(r'^[a-fA-F0-9]{8}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{4}-[a-fA-F0-9]{12}$');
  Future<Directory> _savedScope(int userId, String key) async {
    if (!_key.hasMatch(key)) throw ArgumentError('Invalid saved draft identifier');
    return Directory('${(await _scope(userId, null)).parent.path}/saved/$key');
  }

  Future<Map<String, dynamic>?> read(int userId, int? listingId) async {
    await _queue;
    return _readScope(await _scope(userId, listingId), userId, listingId);
  }

  Future<Map<String, dynamic>?> _readScope(Directory scope, int userId, int? listingId) async {
    try {
      final file = File('${scope.path}/state.json');
      if (!await file.exists() || await file.length() > 1048576) return null;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic> || decoded['version'] != 1 || decoded['user_id'] != userId || decoded['listing_id'] != (listingId ?? 0)) return null;
      final raw = decoded['data'];
      if (raw is! Map<String, dynamic>) return null;
      final data = Map<String, dynamic>.from(raw);
      final images = <String>[];
      final tokens = <String,String>{};
      final keys = (decoded['image_keys'] as List? ?? const []).whereType<String>().toList();
      final oldTokens = (data['image_tokens'] as Map? ?? const {}).values.whereType<String>().toList();
      var index = 0;
      for (final name in (decoded['image_files'] as List? ?? const []).take(12)) {
        if (name is! String || !RegExp(r'^[a-zA-Z0-9_-]+\.(jpg|jpeg|png|webp)$').hasMatch(name)) continue;
        final image = File('${scope.path}/media/$name');
        if (await image.exists()) {
          images.add(image.path);
          if (index < keys.length && keys[index].isNotEmpty) { tokens[image.path] = keys[index]; }
          else if (oldTokens.length == (decoded['image_files'] as List).length && oldTokens[index].isNotEmpty) { tokens[image.path] = oldTokens[index]; }
        }
        index++;
      }
      data['image_paths'] = images;
      data['image_tokens'] = tokens;
      final proof = decoded['proof_file'];
      data.remove('ownership_proof_path');
      if (proof is String && RegExp(r'^[a-zA-Z0-9_-]+\.(jpg|jpeg|png|webp)$').hasMatch(proof)) {
        final file = File('${scope.path}/media/$proof');
        if (await file.exists()) data['ownership_proof_path'] = file.path;
      }
      return data;
    } catch (_) { return null; }
  }

  Future<List<Map<String, dynamic>>> saved(int userId) async {
    await _queue;
    final directory = Directory('${(await _scope(userId, null)).parent.path}/saved');
    if (!await directory.exists()) return const [];
    final rows = <Map<String, dynamic>>[];
    await for (final item in directory.list()) {
      final key = item.uri.pathSegments.where((part) => part.isNotEmpty).last;
      if (item is! Directory || !_key.hasMatch(key)) continue;
      final row = await _readScope(item, userId, null);
      if (row != null) rows.add(row);
    }
    return rows;
  }

  Future<void> pinExplicitSave(int userId, {bool preserveUnclassified = false}) {
    final operation = _queue.then<void>((_) async {
      final source = await _scope(userId, null);
      final data = await _readScope(source, userId, null);
      if (data == null) {
        if (await File('${source.path}/state.json').exists()) throw const FileSystemException('Cannot protect the saved draft');
        return;
      }
      if (!preserveUnclassified && data['draft_kind'] != 'saved' && data['server_property_id'] == null) return;
      final key = data['draft_key'];
      if (key is! String || !_key.hasMatch(key)) throw const FileSystemException('Cannot protect a draft without its identifier');
      final destination = await _savedScope(userId, key);
      final media = Directory('${destination.path}/media'); await media.create(recursive: true);
      final state = Map<String, dynamic>.from(jsonDecode(await File('${source.path}/state.json').readAsString()) as Map);
      final files = <String>[...(state['image_files'] as List).cast<String>(), if (state['proof_file'] is String) state['proof_file'] as String];
      for (final name in files) {
        if (!RegExp(r'^[a-zA-Z0-9_-]+\.(jpg|jpeg|png|webp)$').hasMatch(name)) throw const FileSystemException('Invalid saved media');
        final target = File('${media.path}/$name');
        if (!await target.exists()) await File('${source.path}/media/$name').copy(target.path);
      }
      (state['data'] as Map)['draft_kind'] = 'saved';
      final pending = File('${destination.path}/state.pending');
      await pending.writeAsString(jsonEncode(state), flush: true); await pending.rename('${destination.path}/state.json');
      await for (final file in media.list()) {
        if (file is File && !files.contains(file.uri.pathSegments.last)) await file.delete();
      }
    });
    _queue = operation.then<void>((_) {}, onError: (_, __) {});
    return operation;
  }

  Future<void> deleteSaved(int userId, String key) {
    final operation = _queue.then<void>((_) async {
      final scope = await _savedScope(userId, key);
      if (await scope.exists()) await scope.delete(recursive: true);
    });
    _queue = operation.then<void>((_) {}, onError: (_, __) {});
    return operation;
  }

  Future<void> write(int userId, int? listingId, Map<String, dynamic> snapshot, List<String> imagePaths) {
    final encoded = jsonEncode(snapshot);
    final paths = List<String>.of(imagePaths.take(12));
    final operation = _queue.then<void>((_) async {
      final scope = await _scope(userId, listingId);
      final media = Directory('${scope.path}/media');
      await media.create(recursive: true);
      final names = <String>[], keys = <String>[];
      final data = Map<String,dynamic>.from(jsonDecode(encoded) as Map);
      final originalTokens = (data['image_tokens'] as Map? ?? const {});
      final tokens = <String,String>{};
      for (final path in paths) {
        final source = File(path);
        if (!await source.exists()) throw FileSystemException('Selected image is no longer available');
        final key = originalTokens[path]?.toString() ?? '';
        if (source.parent.path == media.path) {
          names.add(source.uri.pathSegments.last); keys.add(key); tokens[source.path]=key; continue;
        }
        final stat = await source.stat();
        var hash = 2166136261;
        for (final byte in utf8.encode('$path:${stat.size}:${stat.modified.millisecondsSinceEpoch}')) { hash = ((hash ^ byte) * 16777619) & 0xffffffff; }
        final extension = path.split('.').last.toLowerCase();
        final safeExtension = const ['jpg', 'jpeg', 'png', 'webp'].contains(extension) ? extension : 'jpg';
        final name = 'image-${hash.toRadixString(16)}.$safeExtension';
        final target = File('${media.path}/$name');
        if (!await target.exists()) await source.copy(target.path);
        names.add(name); keys.add(key); tokens[target.path]=key;
      }
      String? proofName;
      final proofPath = data['ownership_proof_path'];
      if (proofPath is String && proofPath.isNotEmpty) {
        final source=File(proofPath);
        if (!await source.exists()) throw FileSystemException('Selected private proof is no longer available');
        if (source.parent.path == media.path) { proofName=source.uri.pathSegments.last; }
        else {
          final stat=await source.stat();
          final ext=const ['jpg','jpeg','png','webp'].contains(proofPath.split('.').last.toLowerCase()) ? proofPath.split('.').last.toLowerCase() : 'jpg';
          proofName='proof-${stat.size}-${stat.modified.microsecondsSinceEpoch}.$ext';
          final target=File('${media.path}/$proofName');
          if (!await target.exists()) await source.copy(target.path);
        }
        data['ownership_proof_path']='${media.path}/$proofName';
      }
      data['image_tokens']=tokens;
      final state = {'version': 1, 'user_id': userId, 'listing_id': listingId ?? 0,
        'saved_at': DateTime.now().toUtc().toIso8601String(), 'data': data, 'image_files': names,
        'image_keys': keys, if (proofName != null) 'proof_file':proofName};
      final pending = File('${scope.path}/state.pending');
      await pending.writeAsString(jsonEncode(state), flush: true);
      await pending.rename('${scope.path}/state.json');
      // Only media no longer referenced by the committed recovery state is removed.
      await for (final file in media.list()) {
        if (file is File && !names.contains(file.uri.pathSegments.last) && file.uri.pathSegments.last != proofName) await file.delete();
      }
    });
    _queue = operation.then<void>((_) {}, onError: (_, __) {});
    return operation;
  }

  Future<void> clear(int userId, int? listingId) {
    final operation = _queue.then<void>((_) async { final scope = await _scope(userId, listingId); if (await scope.exists()) await scope.delete(recursive: true); });
    _queue = operation.then<void>((_) {}, onError: (_, __) {});
    return operation;
  }
}
