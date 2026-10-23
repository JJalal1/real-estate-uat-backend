import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ContactActions {
  const ContactActions();
  static const _channel = MethodChannel('real_estate/contact');
  Future<bool> openDialer(String phone) async {
    if (!RegExp(r'^\+?[0-9]{7,15}$').hasMatch(phone)) return false;
    try { return await _channel.invokeMethod<bool>('openDialer', {'phone': phone}) ?? false; }
    on PlatformException { return false; }
    on MissingPluginException { return false; }
  }
}

final contactActionsProvider = Provider<ContactActions>((ref) => const ContactActions());
