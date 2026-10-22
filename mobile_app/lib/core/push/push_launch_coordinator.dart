import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../router/app_router.dart';
import '../../features/account/data/auth_controller.dart';
import '../../features/messages/data/push_registration_repository.dart';

class PushLaunchCoordinator extends ConsumerStatefulWidget {
  const PushLaunchCoordinator({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<PushLaunchCoordinator> createState() =>
      _PushLaunchCoordinatorState();
}

class _PushLaunchCoordinatorState extends ConsumerState<PushLaunchCoordinator>
    with WidgetsBindingObserver {
  static const MethodChannel _channel = MethodChannel('real_estate/push');
  bool _consuming = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _consumeRoute());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _consumeRoute();
      _syncRegistration();
    }
  }

  Future<void> _syncRegistration() async {
    if (ref.read(authControllerProvider).asData?.value == null) return;
    try {
      await ref.read(pushRegistrationRepositoryProvider).syncIfGranted();
    } catch (_) {
      // Token refresh/sync is best-effort and never blocks app resume.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _consumeRoute() async {
    if (_consuming) return;
    _consuming = true;
    try {
      final route = (await _channel.invokeMethod<String>('consumeRoute'))?.trim();
      if (!mounted || route == null || !_allowed(route)) return;
      ref.read(appRouterProvider).go(route);
    } on MissingPluginException {
      // Push is Android-only today; other platforms continue normally.
    } on PlatformException {
      // A malformed/disabled push provider must never block app startup.
    } finally {
      _consuming = false;
    }
  }

  bool _allowed(String route) {
    if (route == '/notifications') return true;
    return RegExp(r'^/properties/[1-9][0-9]*$').hasMatch(route) ||
        RegExp(r'^/messages/[1-9][0-9]*$').hasMatch(route);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
