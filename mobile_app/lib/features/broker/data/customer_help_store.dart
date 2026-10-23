import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

final customerHelpStoreProvider = Provider<CustomerHelpStore>((ref) => CustomerHelpStore());

/// A separate per-account presentation preference; no customer data is stored.
class CustomerHelpStore {
  Future<File> _file(int accountId) async => File('${(await getApplicationSupportDirectory()).path}/customer_help_${accountId}_v1');
  Future<bool> seen(int accountId) async {
    try { return await (await _file(accountId)).exists(); } catch (_) { return false; }
  }
  Future<void> markSeen(int accountId) async {
    try { final file = await _file(accountId); await file.parent.create(recursive: true); await file.writeAsString('seen', flush: true); } catch (_) { /* A help preference never blocks customer work. */ }
  }
}
