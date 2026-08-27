import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../data/auth_controller.dart';
import '../data/broker_verification_repository.dart';
import '../domain/broker_verification.dart';

class BrokerVerificationAdminScreen extends ConsumerStatefulWidget {
  const BrokerVerificationAdminScreen({super.key});

  @override
  ConsumerState<BrokerVerificationAdminScreen> createState() =>
      _BrokerVerificationAdminScreenState();
}

class _BrokerVerificationAdminScreenState
    extends ConsumerState<BrokerVerificationAdminScreen> {
  late Future<List<BrokerVerificationApplication>> _future;
  final Set<int> _busy = <int>{};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() =>
      _future = ref.read(brokerVerificationRepositoryProvider).queue();

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).asData?.value;
    final allowed = user?.isPlatformOwner == true ||
        user?.hasPermission('brokers.verify_accounts') == true;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('توثيق حسابات الدلالين')),
        body: !allowed
            ? const Center(
                child: Text('ليست لديك صلاحية توثيق حسابات الدلالين.'))
            : FutureBuilder<List<BrokerVerificationApplication>>(
                future: _future,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snapshot.hasError) {
                    return Center(
                        child: FilledButton(
                            onPressed: () => setState(_reload),
                            child: const Text('إعادة المحاولة')));
                  }
                  final rows = snapshot.data ?? const [];
                  if (rows.isEmpty) {
                    return const Center(
                        child: Text('لا توجد طلبات توثيق معلقة.'));
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(14),
                    itemCount: rows.length,
                    itemBuilder: (context, index) => _ApplicationCard(
                      application: rows[index],
                      busy: _busy.contains(rows[index].userId),
                      loadDocument: (kind) => ref
                          .read(brokerVerificationRepositoryProvider)
                          .documentBytes(rows[index].userId, kind),
                      onApprove: () => _approve(rows[index]),
                      onReject: () => _reject(rows[index]),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _approve(BrokerVerificationApplication application) async {
    setState(() => _busy.add(application.userId));
    try {
      await ref
          .read(brokerVerificationRepositoryProvider)
          .approve(application.userId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تم توثيق حساب الدلال.')));
        setState(_reload);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
      }
    } finally {
      if (mounted) {
        setState(() => _busy.remove(application.userId));
      }
    }
  }

  Future<void> _reject(BrokerVerificationApplication application) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('سبب رفض التوثيق'),
        content: TextField(
            controller: controller,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(border: OutlineInputBorder())),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, controller.text.trim()),
              child: const Text('رفض وإرسال الملاحظة')),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || reason.length < 3) {
      return;
    }
    setState(() => _busy.add(application.userId));
    try {
      await ref
          .read(brokerVerificationRepositoryProvider)
          .reject(application.userId, reason);
      if (mounted) {
        setState(_reload);
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
      }
    } finally {
      if (mounted) {
        setState(() => _busy.remove(application.userId));
      }
    }
  }
}

class _ApplicationCard extends StatelessWidget {
  const _ApplicationCard(
      {required this.application,
      required this.busy,
      required this.loadDocument,
      required this.onApprove,
      required this.onReject});
  final BrokerVerificationApplication application;
  final bool busy;
  final Future<Uint8List> Function(String kind) loadDocument;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 14),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(application.name,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            Text(application.phone ?? ''),
            const SizedBox(height: 12),
            const Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _DocPreview(kind: 'id_front'),
                _DocPreview(kind: 'id_back'),
                _DocPreview(kind: 'selfie'),
              ],
            ),
            const SizedBox(height: 10),
            for (final kind in const ['id_front', 'id_back', 'selfie'])
              FutureBuilder<Uint8List>(
                future: loadDocument(kind),
                builder: (context, snapshot) {
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.memory(snapshot.data!,
                            height: 180, fit: BoxFit.cover)),
                  );
                },
              ),
            Row(
              children: [
                Expanded(
                    child: FilledButton.icon(
                        onPressed: busy ? null : onApprove,
                        icon: const Icon(Icons.check),
                        label: const Text('توثيق'))),
                const SizedBox(width: 8),
                Expanded(
                    child: OutlinedButton.icon(
                        onPressed: busy ? null : onReject,
                        icon: const Icon(Icons.close),
                        label: const Text('رفض'))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _DocPreview extends StatelessWidget {
  const _DocPreview({required this.kind});
  final String kind;
  @override
  Widget build(BuildContext context) {
    final label = switch (kind) {
      'id_front' => 'البطاقة الأمامية',
      'id_back' => 'البطاقة الخلفية',
      _ => 'السلفي'
    };
    return Chip(label: Text(label));
  }
}
