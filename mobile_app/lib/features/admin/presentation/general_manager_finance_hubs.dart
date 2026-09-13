import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../financial/data/financial_repository.dart';
import 'general_manager_finance_screens.dart';
import 'general_manager_pages.dart';

class GeneralManagerHomeFinancialOverlay extends ConsumerWidget {
  const GeneralManagerHomeFinancialOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Stack(
      children: [
        const GeneralManagerHomeScreen(),
        PositionedDirectional(
          start: 12,
          end: 12,
          bottom: 10,
          child: FutureBuilder<Map<String, dynamic>>(
            future: ref.read(financialRepositoryProvider).adminSummary(period: '30d'),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const SizedBox.shrink();
              final data = snapshot.data!;
              final waiting = data['payments_waiting_review'] ?? 0;
              final overdue = data['overdue_accounts'] ?? 0;
              final holds = data['active_financial_holds'] ?? 0;
              final payouts = _money(data['pending_payouts_amount']);
              return Card(
                elevation: 6,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const GeneralManagerFinanceWorkspaceScreen(),
                  )),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(children: [
                      const Icon(Icons.account_balance_outlined),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'مالية: $waiting تحقق • $overdue متأخر • $holds قيود • $payouts مستحق للمعلنين',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const Icon(Icons.chevron_left),
                    ]),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  static String _money(dynamic value) {
    final number = value is num ? value.toDouble() : double.tryParse('${value ?? 0}') ?? 0;
    return '${number.toStringAsFixed(number == number.roundToDouble() ? 0 : 2)} YER';
  }
}

class GeneralManagerAdministrationFinancialHubScreen extends StatelessWidget {
  const GeneralManagerAdministrationFinancialHubScreen({super.key});

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: const Text('الإدارة')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(14),
                  child: Text(
                      'إدارة المنصة والهيكل والصلاحيات وطرق الدفع. الأعمال اليومية تبقى لدى فرق الدعم.'),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.account_tree_outlined),
                  title: const Text('المنظمة والحسابات والصلاحيات', style: TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: const Text('الموظفون والفرق والحسابات والأدوار والمناطق.'),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const GeneralManagerAdministrationScreen(),
                  )),
                ),
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.account_balance_wallet_outlined),
                  title: const Text('إدارة طرق الدفع', style: TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: const Text('التفعيل، المستفيد، الحساب، الحدود، الدفع الكامل والسعي فقط.'),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const GeneralManagerPaymentMethodsScreen(),
                  )),
                ),
              ),
            ],
          ),
        ),
      );
}

class GeneralManagerReportsFinancialHubScreen extends ConsumerWidget {
  const GeneralManagerReportsFinancialHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: const Text('التقارير')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              FutureBuilder<Map<String, dynamic>>(
                future: ref.read(financialRepositoryProvider).adminSummary(period: '30d'),
                builder: (context, snapshot) {
                  final data = snapshot.data;
                  return Card(
                    child: ListTile(
                      leading: const Icon(Icons.account_balance_outlined),
                      title: const Text('المالية', style: TextStyle(fontWeight: FontWeight.w900)),
                      subtitle: data == null
                          ? const Text('فتح لوحة المالية التفصيلية')
                          : Text('قيمة الصفقات: ${_money(data['gross_transaction_value'])}\nمستحقات غير محصلة: ${_money(data['open_receivables_amount'])}'),
                      isThreeLine: data != null,
                      trailing: const Icon(Icons.chevron_left),
                      onTap: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const GeneralManagerFinanceWorkspaceScreen(),
                      )),
                    ),
                  );
                },
              ),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.analytics_outlined),
                  title: const Text('تقارير السوق والرحلة والتشغيل', style: TextStyle(fontWeight: FontWeight.w900)),
                  subtitle: const Text('التقارير التنفيذية الحالية للسوق والرحلة وفريق الدعم.'),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const GeneralManagerReportsScreen(),
                  )),
                ),
              ),
            ],
          ),
        ),
      );

  static String _money(dynamic value) {
    final number = value is num ? value.toDouble() : double.tryParse('${value ?? 0}') ?? 0;
    return '${number.toStringAsFixed(number == number.roundToDouble() ? 0 : 2)} YER';
  }
}
