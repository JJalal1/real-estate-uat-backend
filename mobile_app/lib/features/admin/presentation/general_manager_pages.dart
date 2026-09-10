import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../../account/presentation/access_control_screen.dart';
import '../../regions/presentation/platform_regions_screen.dart';
import '../../support/presentation/support_workspace_pages.dart';
import '../data/general_manager_repository.dart';
import '../domain/general_manager_insights.dart';

class GeneralManagerHomeScreen extends ConsumerWidget {
  const GeneralManagerHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _ExecutiveDataPage(
      title: 'الرئيسية',
      builder: (context, data, refresh) {
        final overdue = data.overviewCount('overdue_support_tasks');
        final escalated = data.overviewCount('escalated_support_tasks');
        final critical = data.overviewCount('critical_reports');
        final reviewBacklog = data.overviewCount('pending_listing_reviews');
        final verificationBacklog = data.overviewCount('pending_verifications');
        final attention = overdue + escalated + critical;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _ExecutiveHero(
              healthy: attention == 0,
              title: attention == 0
                  ? 'المنصة تعمل بصورة طبيعية'
                  : 'هناك $attention أمور تشغيلية تحتاج انتباه الإدارة',
              subtitle: attention == 0
                  ? 'لا توجد حالات حرجة أو متأخرة أو مصعدة حاليًا.'
                  : 'اعرف موضع الخلل والمسؤول عنه قبل الدخول في التفاصيل التشغيلية.',
            ),
            const SizedBox(height: 20),
            const _SectionTitle('يحتاج انتباهك الآن'),
            const SizedBox(height: 10),
            if (attention == 0 && reviewBacklog == 0 && verificationBacklog == 0)
              const _InfoPanel(
                icon: Icons.check_circle_outline,
                title: 'لا توجد استثناءات إدارية معلقة',
                subtitle: 'استمر في متابعة النمو والأداء من الأقسام أدناه.',
              )
            else
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  if (overdue > 0)
                    _AttentionCard(label: 'حالات دعم متأخرة', value: overdue),
                  if (escalated > 0)
                    _AttentionCard(label: 'حالات مصعدة', value: escalated),
                  if (critical > 0)
                    _AttentionCard(label: 'بلاغات حرجة', value: critical),
                  if (reviewBacklog > 0)
                    _AttentionCard(label: 'إعلانات تنتظر المراجعة', value: reviewBacklog),
                  if (verificationBacklog > 0)
                    _AttentionCard(label: 'طلبات تحقق معلقة', value: verificationBacklog),
                ],
              ),
            const SizedBox(height: 24),
            const _SectionTitle('أداء اليوم'),
            const SizedBox(height: 10),
            _MetricGrid(items: [
              _Metric('مستخدمون جدد', data.todayCount('new_users'), Icons.person_add_alt_1_outlined),
              _Metric('عقارات نُشرت اليوم', data.todayCount('published_properties'), Icons.add_home_work_outlined),
              _Metric('أعمال دعم جديدة', data.todayCount('new_support_tasks'), Icons.support_agent_outlined),
            ]),
            const SizedBox(height: 24),
            const _SectionTitle('السوق والمنصة'),
            const SizedBox(height: 10),
            _MetricGrid(items: [
              _Metric('العقارات المنشورة', data.marketCount('published_properties'), Icons.apartment_outlined),
              _Metric('للبيع', data.marketCount('published_sale'), Icons.sell_outlined),
              _Metric('للإيجار', data.marketCount('published_rent'), Icons.key_outlined),
              _Metric('الدلالون الموثقون', data.marketCount('approved_brokers'), Icons.real_estate_agent_outlined),
            ]),
            const SizedBox(height: 24),
            const _SectionTitle('الفرق'),
            const SizedBox(height: 10),
            _MetricGrid(items: [
              _Metric('موظفو الدعم', data.teamCount('support_agents'), Icons.support_agent_outlined),
              _Metric('مديرو الدعم', data.teamCount('support_managers'), Icons.supervisor_account_outlined),
            ]),
          ],
        );
      },
    );
  }
}

class GeneralManagerMarketScreen extends ConsumerWidget {
  const GeneralManagerMarketScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _ExecutiveDataPage(
      title: 'السوق',
      builder: (context, data, refresh) {
        final types = data.marketList('by_type');
        final governorates = data.marketList('by_governorate');
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            const _InfoPanel(
              icon: Icons.query_stats_outlined,
              title: 'صورة السوق داخل المنصة',
              subtitle: 'هذه المؤشرات مبنية فقط على العقارات والأنشطة المسجلة فعليًا في المنصة، وليست تقييمًا للسوق الخارجي.',
            ),
            const SizedBox(height: 20),
            const _SectionTitle('العقارات'),
            const SizedBox(height: 10),
            _MetricGrid(items: [
              _Metric('إجمالي العقارات', data.marketCount('properties_total'), Icons.home_work_outlined),
              _Metric('منشورة', data.marketCount('published_properties'), Icons.verified_outlined),
              _Metric('بيع', data.marketCount('published_sale'), Icons.sell_outlined),
              _Metric('إيجار', data.marketCount('published_rent'), Icons.key_outlined),
            ]),
            const SizedBox(height: 22),
            const _SectionTitle('الدلالون والمكاتب'),
            const SizedBox(height: 10),
            _MetricGrid(items: [
              _Metric('دلالون موثقون', data.marketCount('approved_brokers'), Icons.real_estate_agent_outlined),
              _Metric('مكاتب موثقة', data.marketCount('approved_offices'), Icons.business_outlined),
              _Metric('تحقق مهني معلق', data.marketCount('pending_professional_verifications'), Icons.hourglass_top_outlined),
            ]),
            const SizedBox(height: 22),
            const _SectionTitle('حسب نوع العقار'),
            const SizedBox(height: 8),
            if (types.isEmpty)
              const _EmptyPanel('لا توجد عقارات منشورة كافية للتقسيم حسب النوع.')
            else
              _DataList(
                rows: types.map((row) => _DataRow(
                  _propertyTypeLabel(row['type']?.toString() ?? ''),
                  _asInt(row['total']),
                )).toList(growable: false),
              ),
            const SizedBox(height: 22),
            const _SectionTitle('حسب المحافظة'),
            const SizedBox(height: 8),
            if (governorates.isEmpty)
              const _EmptyPanel('لا توجد بيانات جغرافية مرتبطة بعقارات منشورة حاليًا.')
            else
              ...governorates.map((row) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(row['name']?.toString() ?? 'محافظة', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _MiniChip('الكل', _asInt(row['total'])),
                              _MiniChip('بيع', _asInt(row['sale'])),
                              _MiniChip('إيجار', _asInt(row['rent'])),
                            ],
                          ),
                        ],
                      ),
                    ),
                  )),
          ],
        );
      },
    );
  }
}

class GeneralManagerAdministrationScreen extends StatelessWidget {
  const GeneralManagerAdministrationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('الإدارة')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            const _InfoPanel(
              icon: Icons.account_tree_outlined,
              title: 'إدارة المنظمة لا إدارة الطلبات',
              subtitle: 'هنا يدير المدير الحسابات والصلاحيات والفرق والتوزيع الجغرافي. الأعمال اليومية تبقى لدى فريق الدعم.',
            ),
            const SizedBox(height: 22),
            const _SectionTitle('الموظفون والهيكل'),
            const SizedBox(height: 8),
            _AdminTile(
              icon: Icons.groups_2_outlined,
              title: 'الموظفون والفرق',
              subtitle: 'عرض موظفي ومديري الدعم ومؤشرات عملهم دون الدخول في قائمة الطلبات اليومية.',
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SupportTeamScreen())),
            ),
            _AdminTile(
              icon: Icons.admin_panel_settings_outlined,
              title: 'الحسابات والأدوار والصلاحيات',
              subtitle: 'البحث عن الحسابات، إدارة الأدوار والصلاحيات ومراجعة سجل التغييرات المصرح به.',
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AccessControlScreen())),
            ),
            const SizedBox(height: 18),
            const _SectionTitle('المناطق والتوزيع'),
            const SizedBox(height: 8),
            _AdminTile(
              icon: Icons.map_outlined,
              title: 'المحافظات والمديريات',
              subtitle: 'إدارة الهيكل الجغرافي للمنصة. ربط فرق الدعم بالنطاقات سيكون في مرحلة تنظيم إدارة الدعم التالية.',
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const PlatformRegionsScreen())),
            ),
            const SizedBox(height: 18),
            const _SectionTitle('الهيكل الإداري القادم'),
            const SizedBox(height: 8),
            const _InfoPanel(
              icon: Icons.schema_outlined,
              title: 'المدير الرئيسي ← المدير الفرعي ← مدير الدعم ← موظف الدعم',
              subtitle: 'لن نفعّل مديرًا فرعيًا أو Scope جغرافيًا بشكل شكلي قبل بناء قواعد Backend ومنع تصعيد الصلاحيات واختبارها أمنيًا.',
            ),
          ],
        ),
      ),
    );
  }
}

class GeneralManagerReportsScreen extends ConsumerWidget {
  const GeneralManagerReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _ExecutiveDataPage(
      title: 'التقارير',
      builder: (context, data, refresh) {
        final journeyRows = <_DataRow>[
          if (data.journeyCount('conversations') != null)
            _DataRow('المحادثات', data.journeyCount('conversations')!),
          if (data.journeyCount('viewings') != null)
            _DataRow('طلبات المعاينة', data.journeyCount('viewings')!),
          if (data.journeyCount('agreements') != null)
            _DataRow('الاتفاقات', data.journeyCount('agreements')!),
          if (data.journeyCount('rental_contracts') != null)
            _DataRow('عقود الإيجار داخل التطبيق', data.journeyCount('rental_contracts')!),
        ];
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            const _InfoPanel(
              icon: Icons.analytics_outlined,
              title: 'تقارير مبنية على البيانات الفعلية',
              subtitle: 'لا تظهر أرباحًا أو تقييمات سوقية أو نسب نجاح غير قابلة للحساب من النظام الحالي.',
            ),
            const SizedBox(height: 22),
            const _SectionTitle('ملخص اليوم'),
            const SizedBox(height: 10),
            _MetricGrid(items: [
              _Metric('مستخدمون جدد', data.todayCount('new_users'), Icons.person_add_alt_1_outlined),
              _Metric('عقارات منشورة', data.todayCount('published_properties'), Icons.home_work_outlined),
              _Metric('أعمال دعم جديدة', data.todayCount('new_support_tasks'), Icons.support_agent_outlined),
            ]),
            const SizedBox(height: 22),
            const _SectionTitle('رحلة العقار داخل المنصة'),
            const SizedBox(height: 8),
            if (journeyRows.isEmpty)
              const _EmptyPanel('لا توجد جداول رحلة متاحة للتقرير في هذه البيئة.')
            else
              _DataList(rows: journeyRows),
            const SizedBox(height: 22),
            const _SectionTitle('تقارير زمنية أوسع'),
            const SizedBox(height: 8),
            const _InfoPanel(
              icon: Icons.date_range_outlined,
              title: 'أسبوع / شهر / فترة مخصصة',
              subtitle: 'سيتم تفعيلها عندما يدعم الـAPI المقارنة الزمنية الحقيقية. لن نعرض نسب نمو تقديرية أو مصطنعة.',
            ),
            const SizedBox(height: 18),
            const _InfoPanel(
              icon: Icons.account_balance_wallet_outlined,
              title: 'المالية والتقارير',
              subtitle: 'محجوزة للمرحلة القادمة. لا توجد مدفوعات أو إيرادات وهمية في هذه النسخة.',
            ),
          ],
        );
      },
    );
  }
}

class _ExecutiveDataPage extends ConsumerStatefulWidget {
  const _ExecutiveDataPage({required this.title, required this.builder});

  final String title;
  final Widget Function(BuildContext, GeneralManagerInsights, Future<void> Function()) builder;

  @override
  ConsumerState<_ExecutiveDataPage> createState() => _ExecutiveDataPageState();
}

class _ExecutiveDataPageState extends ConsumerState<_ExecutiveDataPage> {
  late Future<GeneralManagerInsights> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(generalManagerRepositoryProvider).insights();
  }

  Future<void> _refresh() async {
    setState(() => _future = ref.read(generalManagerRepositoryProvider).insights());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          actions: [IconButton(tooltip: 'تحديث', onPressed: _refresh, icon: const Icon(Icons.refresh))],
        ),
        body: FutureBuilder<GeneralManagerInsights>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.cloud_off_outlined, size: 44),
                      const SizedBox(height: 12),
                      Text(friendlyApiError(snapshot.error!), textAlign: TextAlign.center),
                      const SizedBox(height: 12),
                      FilledButton.icon(onPressed: _refresh, icon: const Icon(Icons.refresh), label: const Text('إعادة المحاولة')),
                    ],
                  ),
                ),
              );
            }
            return RefreshIndicator(
              onRefresh: _refresh,
              child: widget.builder(context, snapshot.data!, _refresh),
            );
          },
        ),
      ),
    );
  }
}

class _ExecutiveHero extends StatelessWidget {
  const _ExecutiveHero({required this.healthy, required this.title, required this.subtitle});
  final bool healthy;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: healthy ? scheme.primaryContainer : scheme.errorContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(healthy ? Icons.check_circle_outline : Icons.warning_amber_rounded, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(subtitle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900));
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 5),
                Text(subtitle, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ])),
            ],
          ),
        ),
      );
}

class _AttentionCard extends StatelessWidget {
  const _AttentionCard({required this.label, required this.value});
  final String label;
  final int value;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 165,
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$value', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900, color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 8),
              Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
      );
}

class _Metric {
  const _Metric(this.label, this.value, this.icon);
  final String label;
  final int value;
  final IconData icon;
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.items});
  final List<_Metric> items;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        final width = (constraints.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: items.map((item) => SizedBox(
            width: width,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(item.icon),
                  const SizedBox(height: 12),
                  Text('${item.value}', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
                  const SizedBox(height: 5),
                  Text(item.label, style: const TextStyle(fontWeight: FontWeight.w700)),
                ]),
              ),
            ),
          )).toList(growable: false),
        );
      });
}

class _AdminTile extends StatelessWidget {
  const _AdminTile({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          minVerticalPadding: 14,
          leading: Icon(icon),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
          subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: Text(subtitle)),
          trailing: const Icon(Icons.chevron_left),
          onTap: onTap,
        ),
      );
}

class _DataRow {
  const _DataRow(this.label, this.value);
  final String label;
  final int value;
}

class _DataList extends StatelessWidget {
  const _DataList({required this.rows});
  final List<_DataRow> rows;
  @override
  Widget build(BuildContext context) => Card(
        child: Column(
          children: List.generate(rows.length, (index) {
            final row = rows[index];
            return Column(children: [
              ListTile(title: Text(row.label), trailing: Text('${row.value}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17))),
              if (index != rows.length - 1) const Divider(height: 1),
            ]);
          }),
        ),
      );
}

class _MiniChip extends StatelessWidget {
  const _MiniChip(this.label, this.value);
  final String label;
  final int value;
  @override
  Widget build(BuildContext context) => Chip(label: Text('$label: $value'));
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(text)));
}

int _asInt(dynamic value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

String _propertyTypeLabel(String type) => switch (type) {
      'apartment' => 'شقة',
      'house' => 'منزل',
      'villa' => 'فيلا',
      'land' => 'أرض',
      'shop' => 'محل',
      'office' => 'مكتب',
      'farm' => 'مزرعة',
      _ => type.isEmpty ? 'غير محدد' : type,
    };
