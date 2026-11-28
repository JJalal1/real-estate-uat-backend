import 'package:flutter/material.dart';

import '../../../core/widgets/app_components.dart';
import 'general_manager_accounts_screen.dart';
import 'general_manager_finance_screens.dart';
import 'general_manager_operations_screen.dart';

class GeneralManagerAdministrationFinancialHubScreen extends StatelessWidget {
  const GeneralManagerAdministrationFinancialHubScreen({super.key});

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: const AppAppBar(title: 'الإدارة'),
          body: ListView(padding: const EdgeInsets.all(16), children: [
            _entry(
                context,
                'فرق المحافظات',
                'إنشاء الفرق وتعيين المدير والأعضاء',
                Icons.groups_outlined,
                const GeneralManagerOperationsScreen(
                    GeneralManagerSection.teams)),
            _entry(
                context,
                'الحسابات والأدوار',
                'تعديل الأدوار وحالة الحساب',
                Icons.admin_panel_settings_outlined,
                const GeneralManagerAccountsScreen()),
            _entry(
                context,
                'إدارة طرق الدفع',
                'التفعيل والمستفيد والحساب والحدود',
                Icons.account_balance_wallet_outlined,
                const GeneralManagerPaymentMethodsScreen()),
            const SizedBox(height: 14),
            const AppSectionHeader(title: 'الهيكل الإداري'),
            const Card(
                child: Column(children: [
              ListTile(
                  leading: Icon(Icons.admin_panel_settings_outlined),
                  title: Text('المدير العام')),
              ListTile(
                  leading: Icon(Icons.groups_outlined),
                  title: Text('مدير فريق المحافظة')),
              ListTile(
                  leading: Icon(Icons.support_agent_outlined),
                  title: Text('موظف الدعم')),
            ])),
          ]),
        ),
      );

  Widget _entry(BuildContext context, String title, String subtitle,
          IconData icon, Widget page) =>
      Card(
          child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_left),
        onTap: () => Navigator.of(context)
            .push<void>(MaterialPageRoute(builder: (_) => page)),
      ));
}
