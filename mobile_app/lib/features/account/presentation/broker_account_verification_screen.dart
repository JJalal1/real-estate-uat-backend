import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/platform/stage5_media_picker.dart';
import '../data/auth_controller.dart';
import '../data/broker_verification_repository.dart';
import '../domain/broker_verification.dart';

class BrokerAccountVerificationScreen extends ConsumerStatefulWidget {
  const BrokerAccountVerificationScreen({super.key});

  @override
  ConsumerState<BrokerAccountVerificationScreen> createState() =>
      _BrokerAccountVerificationScreenState();
}

class _BrokerAccountVerificationScreenState
    extends ConsumerState<BrokerAccountVerificationScreen> {
  final _picker = const Stage5MediaPicker();
  String? _idFront;
  String? _idBack;
  String? _selfie;
  bool _busy = false;
  late Future<BrokerVerificationApplication> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadStatus();
  }

  @override
  void dispose() {
    _picker.clearTemporaryFiles(<String>[
      if (_idFront != null) _idFront!,
      if (_idBack != null) _idBack!,
      if (_selfie != null) _selfie!,
    ]).catchError((_) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).asData?.value;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('توثيق حساب الدلال'),
          actions: [
            IconButton(
              onPressed: _busy ? null : _reload,
              icon: const Icon(Icons.refresh),
              tooltip: 'تحديث حالة التوثيق',
            ),
          ],
        ),
        body: user == null || !user.isBroker
            ? const Center(child: Text('هذه الصفحة مخصصة لحساب الدلال.'))
            : FutureBuilder<BrokerVerificationApplication>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                      child: FilledButton.icon(
                        onPressed: _reload,
                        icon: const Icon(Icons.refresh),
                        label: const Text('إعادة المحاولة'),
                      ),
                    );
                  }
                  final application = snapshot.data!;
                  return ListView(
                    padding: const EdgeInsets.all(18),
                    children: [
                      _StatusCard(application: application),
                      if (!application.approved) ...[
                        const SizedBox(height: 16),
                        const Text(
                          'أرسل الصور الثلاث التالية إلى فريق الدعم. تبقى خاصة ولا تظهر في الإعلان.',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 14),
                        _PickTile(
                            label: 'صورة البطاقة الأمامية',
                            value: _idFront,
                            onTap: _busy
                                ? null
                                : () => _pick((value) => _idFront = value)),
                        _PickTile(
                            label: 'صورة البطاقة الخلفية',
                            value: _idBack,
                            onTap: _busy
                                ? null
                                : () => _pick((value) => _idBack = value)),
                        _PickTile(
                            label: 'صورة سلفي حديثة',
                            value: _selfie,
                            onTap: _busy
                                ? null
                                : () => _pick((value) => _selfie = value)),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                          onPressed: _busy ? null : _submit,
                          icon: _busy
                              ? const SizedBox.square(
                                  dimension: 18,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2))
                              : const Icon(Icons.verified_user_outlined),
                          label: Text(application.pending
                              ? 'إعادة إرسال طلب التوثيق'
                              : 'إرسال طلب التوثيق'),
                        ),
                      ],
                    ],
                  );
                },
              ),
      ),
    );
  }

  Future<void> _pick(void Function(String) setter) async {
    try {
      final paths = await _picker.pickImages();
      if (!mounted || paths.isEmpty) {
        return;
      }
      final selected = paths.first;
      await _picker.clearTemporaryFiles(paths.skip(1));
      if (!mounted) {
        return;
      }
      setState(() => setter(selected));
    } on PlatformException {
      _message('تعذر فتح معرض الصور.');
    } catch (_) {
      _message('تعذر اختيار الصورة.');
    }
  }

  Future<void> _submit() async {
    if (_idFront == null || _idBack == null || _selfie == null) {
      _message('اختر صورة البطاقة الأمامية والخلفية وصورة السلفي أولاً.');
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(brokerVerificationRepositoryProvider).submit(
            idFrontPath: _idFront!,
            idBackPath: _idBack!,
            selfiePath: _selfie!,
          );
      if (!mounted) {
        return;
      }
      await ref.read(authControllerProvider.notifier).refresh();
      _message('تم إرسال طلب التوثيق إلى فريق الدعم.');
      _reload();
    } catch (error) {
      _message(friendlyApiError(error));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<BrokerVerificationApplication> _loadStatus() async {
    final application =
        await ref.read(brokerVerificationRepositoryProvider).status();
    if (application.approved) {
      await ref.read(authControllerProvider.notifier).refresh();
    }
    return application;
  }

  void _reload() => setState(() => _future = _loadStatus());
  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.application});
  final BrokerVerificationApplication application;

  @override
  Widget build(BuildContext context) {
    final (title, subtitle, icon) = switch (application.status) {
      'approved' => (
          'الحساب موثق',
          'يمكنك الآن رفع إعلانات لأي عقار غير منشور مسبقاً.',
          Icons.verified_outlined
        ),
      'pending' => (
          'قيد مراجعة الدعم',
          'يمكنك تصفح الإعلانات، لكن رفع إعلان يبقى متوقفاً حتى الموافقة.',
          Icons.hourglass_top_outlined
        ),
      'rejected' => (
          'يحتاج إعادة إرسال',
          application.note ?? 'راجع الصور وأعد إرسال طلب التوثيق.',
          Icons.info_outline
        ),
      _ => (
          'التوثيق غير مكتمل',
          'ارفع الصور المطلوبة ليتمكن الدعم من تفعيل نشر الإعلانات.',
          Icons.badge_outlined
        ),
    };
    return Card(
      child: ListTile(
        leading: Icon(icon, size: 34),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
        subtitle: Text(subtitle),
      ),
    );
  }
}

class _PickTile extends StatelessWidget {
  const _PickTile(
      {required this.label, required this.value, required this.onTap});
  final String label;
  final String? value;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: Icon(value == null
              ? Icons.add_photo_alternate_outlined
              : Icons.check_circle_outline),
          title:
              Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          subtitle:
              Text(value == null ? 'اضغط لاختيار الصورة' : 'تم اختيار الصورة'),
          trailing: const Icon(Icons.chevron_left),
          onTap: onTap,
        ),
      );
}
