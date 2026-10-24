import 'package:flutter/material.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/widgets/app_components.dart';
import '../../account/presentation/actor_scoped_page.dart';
import '../data/agreement_repository.dart';
import '../domain/agreement_models.dart';

class AgreementsScreen extends ConsumerWidget {
  const AgreementsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ActorScopedPage(builder: (_) => const _AgreementsScreenForActor());
}

class _AgreementsScreenForActor extends ConsumerStatefulWidget {
  const _AgreementsScreenForActor();

  @override
  ConsumerState<_AgreementsScreenForActor> createState() => _AgreementsPageState();
}

class _AgreementsPageState extends ConsumerState<_AgreementsScreenForActor> {
  List<PropertyAgreement> _agreements = const [];
  List<RentalContract> _contracts = const [];
  bool _loading = true;
  bool _loaded = false;
  String? _error;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    final generation = ++_generation;
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final repo = ref.read(agreementRepositoryProvider);
      final results = await Future.wait<dynamic>([repo.mine(), repo.contractsMine()]);
      if (!mounted || generation != _generation) return;
      setState(() {
        _agreements = results[0] as List<PropertyAgreement>;
        _contracts = results[1] as List<RentalContract>;
        _loading = false;
        _loaded = true;
      });
    } catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _loading = false; _error = friendlyApiError(error);
        if (!isTransientApiFailure(error)) { _agreements = const []; _contracts = const []; _loaded = false; }
      });
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
            IconButton(onPressed: _loading ? null : _load, icon: const EbrokerIcon(Icons.refresh), tooltip: 'تحديث'),
          ],
        ),
        body: _loading && !_loaded
            ? const Center(child: CircularProgressIndicator())
            : _error != null && !_loaded
                ? AppErrorState(message: _error!, onRetry: _load)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      children: [
                        AppRefreshStatus(loading: _loading, error: _error, onRetry: _load),
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
        leading: EbrokerIcon(item.isRental ? Icons.key_outlined : Icons.handshake_outlined),
        title: Text('${item.transactionLabel} • ${moneyLabel(r.agreedAmount, r.currency)}'),
        subtitle: Text('${item.statusLabel}\nمرجع: ${item.reference} • نسخة ${r.revisionNumber}'),
        isThreeLine: true,
        trailing: const EbrokerIcon(Icons.chevron_left),
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
        leading: const EbrokerIcon(Icons.home_work_outlined),
        title: Text(item.propertyTitle),
        subtitle: Text('${item.statusLabel}\n${moneyLabel(r.rentAmount, r.currency)} • ${r.cadenceLabel}'),
        isThreeLine: true,
        trailing: const EbrokerIcon(Icons.chevron_left),
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
          const EbrokerIcon(Icons.info_outline),
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
