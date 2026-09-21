import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../data/agreement_repository.dart';
import '../domain/agreement_models.dart';

class AgreementsScreen extends ConsumerStatefulWidget {
  const AgreementsScreen({super.key});

  @override
  ConsumerState<AgreementsScreen> createState() => _AgreementsScreenState();
}

class _AgreementsScreenState extends ConsumerState<AgreementsScreen> {
  List<PropertyAgreement> _agreements = const [];
  List<RentalContract> _contracts = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final repo = ref.read(agreementRepositoryProvider);
      final results = await Future.wait<dynamic>([repo.mine(), repo.contractsMine()]);
      if (!mounted) return;
      setState(() {
        _agreements = results[0] as List<PropertyAgreement>;
        _contracts = results[1] as List<RentalContract>;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() { _loading = false; _error = friendlyApiError(error); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('اتفاقاتي وعقودي'),
          actions: [
            IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh), tooltip: 'تحديث'),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(onPressed: _load, child: const Text('إعادة المحاولة')),
                      ]),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        const _InfoBanner(),
                        const SizedBox(height: 18),
                        Text('الاتفاقات', style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 8),
                        if (_agreements.isEmpty)
                          const _EmptyCard(text: 'لا توجد اتفاقات بعد. يبدأ الاتفاق من محادثة عقار محدد.')
                        else
                          ..._agreements.map(_agreementCard),
                        const SizedBox(height: 22),
                        Text('عقود الإيجار داخل التطبيق', style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 8),
                        if (_contracts.isEmpty)
                          const _EmptyCard(text: 'لا توجد سجلات عقود إيجار بعد.')
                        else
                          ..._contracts.map(_contractCard),
                      ],
                    ),
                  ),
      ),
    );
  }

  Widget _agreementCard(PropertyAgreement item) {
    final r = item.currentRevision;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: () async {
          await context.push('/agreements/${item.id}');
          if (mounted) _load();
        },
        leading: Icon(item.isRental ? Icons.key_outlined : Icons.handshake_outlined),
        title: Text('${item.transactionLabel} • ${moneyLabel(r.agreedAmount, r.currency)}'),
        subtitle: Text('${item.statusLabel}\nمرجع: ${item.reference} • نسخة ${r.revisionNumber}'),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_left),
      ),
    );
  }

  Widget _contractCard(RentalContract item) {
    final r = item.currentRevision;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: () async {
          await context.push('/rental-contracts/${item.id}');
          if (mounted) _load();
        },
        leading: const Icon(Icons.home_work_outlined),
        title: Text(item.propertyTitle),
        subtitle: Text('${item.statusLabel}\n${moneyLabel(r.rentAmount, r.currency)} • ${r.cadenceLabel}'),
        isThreeLine: true,
        trailing: const Icon(Icons.chevron_left),
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Icon(Icons.info_outline),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'هذه سجلات اتفاق داخل التطبيق. لا تمثل توثيقاً حكومياً أو تسجيل ملكية أو استشارة قانونية، ولا يتم فيها تحصيل أو تحويل أموال.',
            ),
          ),
        ]),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(text, textAlign: TextAlign.center),
        ),
      );
}
