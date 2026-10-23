import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../network/api_client.dart';

class ReleaseGate extends ConsumerStatefulWidget {
  const ReleaseGate({required this.child, super.key});

  final Widget child;

  @override
  ConsumerState<ReleaseGate> createState() => _ReleaseGateState();
}

class _ReleaseGateState extends ConsumerState<ReleaseGate> {
  static const int _buildNumber = int.fromEnvironment(
    'APP_BUILD_NUMBER',
    defaultValue: 1,
  );

  bool _checking = true;
  bool _required = false;
  bool _optionalAvailable = false;
  bool _optionalDismissed = false;
  String? _message;
  Uri? _storeUri;

  @override
  void initState() {
    super.initState();
    Future.microtask(_check);
  }

  Future<void> _check() async {
    try {
      final response = await ref.read(dioProvider).get<Map<String, dynamic>>('/release');
      final data = response.data?['data'];
      if (data is! Map) return;
      final minimum = _asInt(data['minimum_supported_build']) ?? 1;
      final latest = _asInt(data['latest_build']) ?? minimum;
      final store = Uri.tryParse(data['store_url']?.toString() ?? '');
      if (!mounted) return;
      setState(() {
        _required = _buildNumber < minimum;
        _optionalAvailable = !_required && _buildNumber < latest;
        _message = data['message']?.toString();
        _storeUri = store?.hasScheme == true ? store : null;
      });
    } on DioException {
      // A release metadata outage must never lock users out of the app.
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  int? _asInt(dynamic value) =>
      value is num ? value.toInt() : int.tryParse(value?.toString() ?? '');

  @override
  Widget build(BuildContext context) {
    if (_checking) return widget.child;

    if (_required) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Material(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.system_update_alt_rounded, size: 54),
                      const SizedBox(height: 18),
                      Text(
                        'يلزم تحديث عقار',
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        _message?.trim().isNotEmpty == true
                            ? _message!
                            : 'هذا الإصدار قديم ولا يمكن استخدامه بأمان.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 22),
                      FilledButton.icon(
                        onPressed: _storeUri == null
                            ? _check
                            : () => launchUrl(
                                  _storeUri!,
                                  mode: LaunchMode.externalApplication,
                                ),
                        icon: Icon(
                          _storeUri == null
                              ? Icons.refresh_rounded
                              : Icons.open_in_new_rounded,
                        ),
                        label: Text(
                          _storeUri == null ? 'إعادة التحقق' : 'تحديث التطبيق',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    if (!_optionalAvailable || _optionalDismissed || _storeUri == null) {
      return widget.child;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        PositionedDirectional(
          top: 0,
          start: 0,
          end: 0,
          child: SafeArea(
            bottom: false,
            child: MaterialBanner(
              leading: const Icon(Icons.system_update_outlined),
              content: Text(
                _message?.trim().isNotEmpty == true
                    ? _message!
                    : 'يتوفر إصدار أحدث من عقار.',
              ),
              actions: [
                TextButton(
                  onPressed: () => setState(() => _optionalDismissed = true),
                  child: const Text('لاحقًا'),
                ),
                FilledButton(
                  onPressed: () => launchUrl(
                    _storeUri!,
                    mode: LaunchMode.externalApplication,
                  ),
                  child: const Text('تحديث'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
