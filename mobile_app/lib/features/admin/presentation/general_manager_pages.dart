import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../core/network/api_error_message.dart';
import '../../account/presentation/access_control_screen.dart';
import '../../regions/data/region_repository.dart';
import '../../regions/domain/region_models.dart';
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
        final urgentAttention = overdue + escalated + critical;

        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _ExecutiveHero(
              healthy: urgentAttention == 0,
              title: urgentAttention == 0
                  ? 'المنصة تعمل بصورة طبيعية'
                  : 'هناك $urgentAttention أمور تحتاج تدخلك',
              subtitle: urgentAttention == 0
                  ? 'لا توجد حالات حرجة أو متأخرة أو مصعدة حاليًا.'
                  : 'ركّز على الاستثناءات، واترك الأعمال اليومية لفريق الدعم.',
            ),
            const SizedBox(height: 20),
            const _SectionTitle('يحتاج تدخلك الآن'),
            const SizedBox(height: 10),
            if (urgentAttention == 0)
              const _InfoPanel(
                icon: Icons.check_circle_outline,
                title: 'لا توجد استثناءات حرجة',
                subtitle: 'انتقل إلى السوق أو الإدارة لمتابعة الأداء والنمو.',
              )
            else
              _MetricGrid(items: [
                if (overdue > 0)
                  _Metric('حالات دعم متأخرة', overdue, Icons.timer_off_outlined,
                      onTap: () => _openOperations(context, data)),
                if (escalated > 0)
                  _Metric('حالات مصعدة', escalated, Icons.trending_up,
                      onTap: () => _openOperations(context, data)),
                if (critical > 0)
                  _Metric('بلاغات حرجة', critical, Icons.crisis_alert_outlined,
                      onTap: () => _openOperations(context, data)),
              ]),
            const SizedBox(height: 24),
            const _SectionTitle('حالة التشغيل'),
            const SizedBox(height: 10),
            _MetricGrid(items: [
              _Metric('إعلانات قيد المراجعة', reviewBacklog, Icons.fact_check_outlined,
                  onTap: () => _openOperations(context, data)),
              _Metric('طلبات تحقق معلقة', verificationBacklog, Icons.verified_user_outlined,
                  onTap: () => _openOperations(context, data)),
              _Metric('أعمال دعم مفتوحة', data.overviewCount('open_support_tasks'), Icons.support_agent_outlined,
                  onTap: () => _openOperations(context, data)),
            ]),
            const SizedBox(height: 24),
            const _SectionTitle('أداء اليوم'),
            const SizedBox(height: 10),
            _MetricGrid(items: [
              _Metric('مستخدمون جدد', data.todayCount('new_users'), Icons.person_add_alt_1_outlined,
                  onTap: () => _openPeople(context, data)),
              _Metric('عقارات نُشرت اليوم', data.todayCount('published_properties'), Icons.add_home_work_outlined,
                  onTap: () => _openMarket(context, data)),
              _Metric('أعمال دعم جديدة', data.todayCount('new_support_tasks'), Icons.support_agent_outlined,
                  onTap: () => _openOperations(context, data)),
            ]),
            const SizedBox(height: 24),
            _SectionTitle('السوق والمنصة', actionLabel: 'عرض السوق', onAction: () => _openMarket(context, data)),
            const SizedBox(height: 10),
            _MetricGrid(items: [
              _Metric('العقارات المنشورة', data.marketCount('published_properties'), Icons.apartment_outlined,
                  onTap: () => _openMarket(context, data)),
              _Metric('للبيع', data.marketCount('published_sale'), Icons.sell_outlined,
                  onTap: () => _openMarket(context, data)),
              _Metric('للإيجار', data.marketCount('published_rent'), Icons.key_outlined,
                  onTap: () => _openMarket(context, data)),
              _Metric('الدلالون الموثقون', data.marketCount('approved_brokers'), Icons.real_estate_agent_outlined,
                  onTap: () => _openProfessionals(context, data)),
            ]),
            const SizedBox(height: 24),
            _SectionTitle('المنظمة', actionLabel: 'عرض الفريق', onAction: () => _openTeam(context)),
            const SizedBox(height: 10),
            _MetricGrid(items: [
              _Metric('موظفو الدعم', data.teamCount('support_agents'), Icons.support_agent_outlined,
                  onTap: () => _openTeam(context)),
              _Metric('مديرو الدعم', data.teamCount('support_managers'), Icons.supervisor_account_outlined,
                  onTap: () => _openTeam(context)),
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
        final unmapped = data.marketCount('unmapped_published');
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            _ActionPanel(
              icon: Icons.map_outlined,
              title: 'الخريطة الإدارية',
              subtitle: 'ابحث عن محافظة أو مديرية، وانتقل إليها على الخريطة وشاهد مواقع العقارات المنشورة.',
              actionLabel: 'فتح الخريطة',
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => GeneralManagerMapScreen(initialInsights: data),
              )),
            ),
            if (unmapped > 0) ...[
              const SizedBox(height: 10),
              _InfoPanel(
                icon: Icons.info_outline,
                title: '$unmapped عقارات منشورة لم تُربط بعد بحدود إدارية داخلية',
                subtitle: 'مواقعها الجغرافية تظل ظاهرة على الخريطة من الإحداثيات المسجلة، وربط المحافظات والمديريات سيتم تدريجيًا.',
              ),
            ],
            const SizedBox(height: 22),
            const _SectionTitle('العقارات'),
            const SizedBox(height: 10),
            _MetricGrid(items: [
              _Metric('إجمالي العقارات', data.marketCount('properties_total'), Icons.home_work_outlined,
                  onTap: () => _openMarket(context, data)),
              _Metric('منشورة', data.marketCount('published_properties'), Icons.verified_outlined,
                  onTap: () => _openMarket(context, data)),
              _Metric('بيع', data.marketCount('published_sale'), Icons.sell_outlined,
                  onTap: () => _openMarket(context, data)),
              _Metric('إيجار', data.marketCount('published_rent'), Icons.key_outlined,
                  onTap: () => _openMarket(context, data)),
            ]),
            const SizedBox(height: 22),
            _SectionTitle('الدلالون والمكاتب', actionLabel: 'تفاصيل', onAction: () => _openProfessionals(context, data)),
            const SizedBox(height: 10),
            _MetricGrid(items: [
              _Metric('دلالون موثقون', data.marketCount('approved_brokers'), Icons.real_estate_agent_outlined,
                  onTap: () => _openProfessionals(context, data)),
              _Metric('مكاتب موثقة', data.marketCount('approved_offices'), Icons.business_outlined,
                  onTap: () => _openProfessionals(context, data)),
              _Metric('تحقق مهني معلق', data.marketCount('pending_professional_verifications'), Icons.hourglass_top_outlined,
                  onTap: () => _openProfessionals(context, data)),
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
              _ActionPanel(
                icon: Icons.location_off_outlined,
                title: 'لا توجد عقارات مرتبطة بحدود المحافظات بعد',
                subtitle: 'استخدم الخريطة الآن لرؤية مواقع العقارات الفعلية، بينما نربط الحدود الإدارية تدريجيًا.',
                actionLabel: 'فتح الخريطة',
                onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => GeneralManagerMapScreen(initialInsights: data),
                )),
              )
            else
              ...governorates.map((row) => _GovernorateCard(
                    name: row['name']?.toString() ?? 'محافظة',
                    total: _asInt(row['total']),
                    sale: _asInt(row['sale']),
                    rent: _asInt(row['rent']),
                    onTap: () => _openGovernorate(context, row),
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
              subtitle: 'تابع الأشخاص والهيكل والنطاقات والصلاحيات، واترك معالجة الطلبات اليومية لفريق الدعم.',
            ),
            const SizedBox(height: 22),
            const _SectionTitle('الموظفون والهيكل'),
            const SizedBox(height: 8),
            _AdminTile(
              icon: Icons.groups_2_outlined,
              title: 'الموظفون والفرق',
              subtitle: 'ملخص تنفيذي سريع لأداء موظفي ومديري الدعم بدون فتح قائمة الطلبات.',
              onTap: () => _openTeam(context),
            ),
            _AdminTile(
              icon: Icons.admin_panel_settings_outlined,
              title: 'الحسابات والأدوار والصلاحيات',
              subtitle: 'أداة متقدمة لتغيير الأدوار والصلاحيات ومراجعة أثرها الإداري.',
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AccessControlScreen())),
            ),
            const SizedBox(height: 18),
            const _SectionTitle('المناطق والتوزيع'),
            const SizedBox(height: 8),
            _AdminTile(
              icon: Icons.map_outlined,
              title: 'الخريطة والمحافظات',
              subtitle: 'بحث جغرافي سريع ومواقع العقارات المنشورة، مع تجهيز المحافظات للنطاقات الإدارية القادمة.',
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const GeneralManagerMapScreen())),
            ),
            const SizedBox(height: 18),
            const _SectionTitle('الهيكل الإداري'),
            const SizedBox(height: 8),
            const _InfoPanel(
              icon: Icons.schema_outlined,
              title: 'المدير الرئيسي ← المدير الفرعي ← مدير الدعم ← موظف الدعم',
              subtitle: 'الهيكل والصلاحيات الجغرافية التفصيلية ستُفعّل عند تنظيم مدير الدعم وموظف الدعم حتى تبقى الصلاحيات Backend-authoritative وآمنة.',
            ),
          ],
        ),
      ),
    );
  }
}

class GeneralManagerReportsScreen extends ConsumerStatefulWidget {
  const GeneralManagerReportsScreen({super.key});

  @override
  ConsumerState<GeneralManagerReportsScreen> createState() => _GeneralManagerReportsScreenState();
}

class _GeneralManagerReportsScreenState extends ConsumerState<GeneralManagerReportsScreen> {
  String _period = 'day';

  @override
  Widget build(BuildContext context) {
    return _ExecutiveDataPage(
      title: 'التقارير',
      builder: (context, data, refresh) {
        final periodData = data.period(_period);
        final journeyRows = <_DataRow>[
          if (data.journeyCount('conversations') != null) _DataRow('المحادثات', data.journeyCount('conversations')!),
          if (data.journeyCount('viewings') != null) _DataRow('طلبات المعاينة', data.journeyCount('viewings')!),
          if (data.journeyCount('agreements') != null) _DataRow('الاتفاقات', data.journeyCount('agreements')!),
          if (data.journeyCount('rental_contracts') != null) _DataRow('عقود الإيجار داخل التطبيق', data.journeyCount('rental_contracts')!),
        ];
        int p(String key) => _asInt(periodData[key]);
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            const _InfoPanel(
              icon: Icons.analytics_outlined,
              title: 'تقارير مبنية على البيانات الفعلية',
              subtitle: 'لا تظهر أرباحًا أو تقييمات أو نسب نجاح غير قابلة للحساب من النظام الحالي.',
            ),
            const SizedBox(height: 16),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'day', label: Text('اليوم')),
                ButtonSegment(value: '7d', label: Text('7 أيام')),
                ButtonSegment(value: '30d', label: Text('30 يوم')),
              ],
              selected: {_period},
              onSelectionChanged: (value) => setState(() => _period = value.first),
            ),
            const SizedBox(height: 22),
            const _SectionTitle('ملخص الفترة'),
            const SizedBox(height: 10),
            _MetricGrid(items: [
              _Metric('مستخدمون جدد', p('new_users'), Icons.person_add_alt_1_outlined,
                  onTap: () => _openPeople(context, data)),
              _Metric('عقارات منشورة', p('published_properties'), Icons.home_work_outlined,
                  onTap: () => _openMarket(context, data)),
              _Metric('أعمال دعم جديدة', p('new_support_tasks'), Icons.support_agent_outlined,
                  onTap: () => _openOperations(context, data)),
            ]),
            const SizedBox(height: 22),
            const _SectionTitle('رحلة العقار داخل المنصة'),
            const SizedBox(height: 8),
            if (journeyRows.isEmpty)
              const _EmptyPanel('لا توجد جداول رحلة متاحة للتقرير في هذه البيئة.')
            else
              _DataList(rows: journeyRows),
            const SizedBox(height: 22),
            const _InfoPanel(
              icon: Icons.account_balance_wallet_outlined,
              title: 'المالية والتقارير',
              subtitle: 'ستُبنى كقسم مستقل لاحقًا وفق البيانات المالية الحقيقية. لا توجد مدفوعات أو أرباح وهمية هنا.',
            ),
          ],
        );
      },
    );
  }
}

class GeneralManagerTeamScreen extends ConsumerStatefulWidget {
  const GeneralManagerTeamScreen({super.key});

  @override
  ConsumerState<GeneralManagerTeamScreen> createState() => _GeneralManagerTeamScreenState();
}

class _GeneralManagerTeamScreenState extends ConsumerState<GeneralManagerTeamScreen> {
  late Future<List<GeneralManagerTeamMember>> _future;

  @override
  void initState() {
    super.initState();
    _future = ref.read(generalManagerRepositoryProvider).team();
  }

  Future<void> _refresh() async {
    setState(() => _future = ref.read(generalManagerRepositoryProvider).team());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الموظفون والفرق'),
          actions: [IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh), tooltip: 'تحديث')],
        ),
        body: FutureBuilder<List<GeneralManagerTeamMember>>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const _LoadingList(message: 'جاري تحميل حالة الفريق…');
            }
            if (snapshot.hasError) return _PageError(snapshot.error!, _refresh);
            final rows = snapshot.data ?? const <GeneralManagerTeamMember>[];
            if (rows.isEmpty) return const Center(child: Text('لا يوجد موظفو دعم مسجلون.'));
            final managers = rows.where((e) => e.isManager).toList(growable: false);
            final agents = rows.where((e) => !e.isManager).toList(growable: false);
            final open = rows.fold<int>(0, (sum, e) => sum + e.openTasks);
            final overdue = rows.fold<int>(0, (sum, e) => sum + e.overdueTasks);
            return RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  _MetricGrid(items: [
                    _Metric('مديرو الدعم', managers.length, Icons.supervisor_account_outlined),
                    _Metric('موظفو الدعم', agents.length, Icons.support_agent_outlined),
                    _Metric('أعمال مفتوحة', open, Icons.pending_actions_outlined),
                    _Metric('متأخرة', overdue, Icons.timer_off_outlined),
                  ]),
                  const SizedBox(height: 22),
                  if (managers.isNotEmpty) ...[
                    const _SectionTitle('مديرو الدعم'),
                    const SizedBox(height: 8),
                    ...managers.map(_TeamMemberCard.new),
                    const SizedBox(height: 16),
                  ],
                  const _SectionTitle('موظفو الدعم'),
                  const SizedBox(height: 8),
                  ...agents.map(_TeamMemberCard.new),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class GeneralManagerMapScreen extends ConsumerStatefulWidget {
  const GeneralManagerMapScreen({super.key, this.initialInsights});
  final GeneralManagerInsights? initialInsights;

  @override
  ConsumerState<GeneralManagerMapScreen> createState() => _GeneralManagerMapScreenState();
}

class _GeneralManagerMapScreenState extends ConsumerState<GeneralManagerMapScreen> {
  static const _style = 'https://tiles.openfreemap.org/styles/liberty';
  static const _yemen = LatLng(15.5527, 48.5164);
  final _search = TextEditingController();
  Timer? _debounce;
  MapLibreMapController? _map;
  bool _styleLoaded = false;
  bool _mapReady = false;
  bool _searching = false;
  String? _searchError;
  List<GeneralManagerPlaceResult> _results = const [];
  List<GovernorateModel> _governorates = const [];
  int? _governorateId;
  GeneralManagerInsights? _insights;

  @override
  void initState() {
    super.initState();
    _insights = widget.initialInsights;
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final futures = await Future.wait<dynamic>([
        if (_insights == null) ref.read(generalManagerRepositoryProvider).insights(),
        ref.read(regionRepositoryProvider).governorates(),
      ]);
      if (!mounted) return;
      setState(() {
        var index = 0;
        if (_insights == null) _insights = futures[index++] as GeneralManagerInsights;
        _governorates = futures[index] as List<GovernorateModel>;
      });
      await _syncProperties();
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  void _onMapCreated(MapLibreMapController controller) {
    _map = controller;
  }

  Future<void> _onStyleLoaded() async {
    _styleLoaded = true;
    if (mounted) setState(() => _mapReady = true);
    await _syncProperties();
  }

  Future<void> _syncProperties() async {
    final map = _map;
    final insights = _insights;
    if (map == null || !_styleLoaded || insights == null) return;
    try {
      await map.clearCircles();
      final points = <LatLng>[];
      for (final row in insights.marketList('map_properties')) {
        final lat = _asDouble(row['latitude']);
        final lng = _asDouble(row['longitude']);
        if (lat == null || lng == null) continue;
        final point = LatLng(lat, lng);
        points.add(point);
        await map.addCircle(CircleOptions(
          geometry: point,
          circleRadius: 7,
          circleColor: '#0B8A55',
          circleStrokeColor: '#FFFFFF',
          circleStrokeWidth: 2,
        ));
      }
      if (points.isNotEmpty && widget.initialInsights == null) {
        final lat = points.fold<double>(0, (s, p) => s + p.latitude) / points.length;
        final lng = points.fold<double>(0, (s, p) => s + p.longitude) / points.length;
        await map.animateCamera(CameraUpdate.newLatLngZoom(LatLng(lat, lng), 6.2));
      }
    } catch (_) {}
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    final query = value.trim();
    if (query.length < 2) {
      setState(() {
        _results = const [];
        _searching = false;
        _searchError = null;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 450), () => _searchPlaces(query));
  }

  Future<void> _searchPlaces(String query) async {
    setState(() {
      _searching = true;
      _searchError = null;
    });
    try {
      final rows = await ref.read(generalManagerRepositoryProvider).searchPlaces(query);
      if (!mounted || _search.text.trim() != query) return;
      setState(() {
        _results = rows;
        _searching = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _results = const [];
        _searching = false;
        _searchError = friendlyApiError(error);
      });
    }
  }

  Future<void> _focusPlace(GeneralManagerPlaceResult place) async {
    FocusScope.of(context).unfocus();
    setState(() => _results = const []);
    final map = _map;
    if (map == null) return;
    await map.animateCamera(CameraUpdate.newLatLngZoom(LatLng(place.latitude, place.longitude), 11.5));
  }

  Future<void> _focusGovernorate(GovernorateModel gov) async {
    setState(() => _governorateId = gov.id);
    _search.text = gov.nameAr;
    await _searchPlaces(gov.nameAr);
    if (_results.isNotEmpty) await _focusPlace(_results.first);
  }

  Future<void> _showYemen() async {
    setState(() {
      _governorateId = null;
      _results = const [];
      _search.clear();
    });
    await _map?.animateCamera(CameraUpdate.newLatLngZoom(_yemen, 5.2));
  }

  @override
  Widget build(BuildContext context) {
    final markers = _insights?.marketList('map_properties').length ?? 0;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('الخريطة الإدارية')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
          children: [
            TextField(
              controller: _search,
              onChanged: _onSearchChanged,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                labelText: 'ابحث عن محافظة أو مديرية أو منطقة',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searching
                    ? const Padding(padding: EdgeInsets.all(14), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                    : null,
              ),
            ),
            if (_searchError != null)
              Padding(padding: const EdgeInsets.only(top: 8), child: Text(_searchError!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
            if (_results.isNotEmpty)
              Card(
                margin: const EdgeInsets.only(top: 6),
                child: Column(
                  children: _results.take(6).map((place) => ListTile(
                    leading: const Icon(Icons.place_outlined),
                    title: Text(place.label, maxLines: 2, overflow: TextOverflow.ellipsis),
                    onTap: () => _focusPlace(place),
                  )).toList(growable: false),
                ),
              ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: DropdownButtonFormField<int>(
                  value: _governorateId,
                  decoration: const InputDecoration(labelText: 'المحافظة', prefixIcon: Icon(Icons.location_city_outlined)),
                  hint: const Text('كل اليمن'),
                  items: _governorates.map((gov) => DropdownMenuItem(value: gov.id, child: Text(gov.nameAr))).toList(growable: false),
                  onChanged: (value) {
                    if (value == null) return;
                    final gov = _governorates.firstWhere((e) => e.id == value);
                    _focusGovernorate(gov);
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(onPressed: _showYemen, tooltip: 'عرض اليمن بالكامل', icon: const Icon(Icons.public)),
            ]),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(
                height: 390,
                child: Stack(children: [
                  MapLibreMap(
                    styleString: _style,
                    initialCameraPosition: const CameraPosition(target: _yemen, zoom: 5.2),
                    onMapCreated: _onMapCreated,
                    onStyleLoadedCallback: _onStyleLoaded,
                    myLocationEnabled: false,
                    compassEnabled: true,
                    rotateGesturesEnabled: true,
                  ),
                  if (!_mapReady)
                    const Positioned.fill(child: ColoredBox(color: Color(0x99FFFFFF), child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [CircularProgressIndicator(), SizedBox(height: 10), Text('جاري تحميل الخريطة…')])))),
                ]),
              ),
            ),
            const SizedBox(height: 12),
            _InfoPanel(
              icon: Icons.home_work_outlined,
              title: '$markers عقارات منشورة بمواقع جغرافية',
              subtitle: 'النقاط الخضراء تمثل مواقع العقارات المنشورة الفعلية. لا يتم عرض مواقع المستخدمين الشخصية.',
            ),
            const SizedBox(height: 10),
            const _InfoPanel(
              icon: Icons.layers_outlined,
              title: 'طبقات إدارية قادمة مع تنظيم الدعم',
              subtitle: 'عند بناء نطاقات مدير الدعم وموظفيه سنضيف طبقة فرق الدعم والأحمال حسب المحافظة، بدون خلطها الآن مع تجربة المدير.',
            ),
          ],
        ),
      ),
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
        appBar: AppBar(title: Text(widget.title), actions: [IconButton(tooltip: 'تحديث', onPressed: _refresh, icon: const Icon(Icons.refresh))]),
        body: FutureBuilder<GeneralManagerInsights>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) return const _LoadingList(message: 'جاري تجهيز لوحة المدير…');
            if (snapshot.hasError) return _PageError(snapshot.error!, _refresh);
            return RefreshIndicator(onRefresh: _refresh, child: widget.builder(context, snapshot.data!, _refresh));
          },
        ),
      ),
    );
  }
}

class _LoadingList extends StatelessWidget {
  const _LoadingList({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    padding: const EdgeInsets.all(24),
    children: [const SizedBox(height: 140), const Center(child: CircularProgressIndicator()), const SizedBox(height: 14), Center(child: Text(message))],
  );
}

class _PageError extends StatelessWidget {
  const _PageError(this.error, this.retry);
  final Object error;
  final Future<void> Function() retry;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [const SizedBox(height: 100), const Icon(Icons.cloud_off_outlined, size: 48), const SizedBox(height: 12), Text(friendlyApiError(error), textAlign: TextAlign.center), const SizedBox(height: 12), FilledButton.icon(onPressed: retry, icon: const Icon(Icons.refresh), label: const Text('إعادة المحاولة'))],
  );
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
      decoration: BoxDecoration(color: healthy ? scheme.primaryContainer : scheme.errorContainer, borderRadius: BorderRadius.circular(20)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(healthy ? Icons.check_circle_outline : Icons.warning_amber_rounded, size: 30),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 6), Text(subtitle),
        ])),
      ]),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.actionLabel, this.onAction});
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: Text(text, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900))),
    if (actionLabel != null && onAction != null) TextButton(onPressed: onAction, child: Text(actionLabel!)),
  ]);
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Card(child: Padding(padding: const EdgeInsets.all(16), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Icon(icon), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w900)), const SizedBox(height: 5), Text(subtitle, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))])),
  ])));
}

class _ActionPanel extends StatelessWidget {
  const _ActionPanel({required this.icon, required this.title, required this.subtitle, required this.actionLabel, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(child: InkWell(borderRadius: BorderRadius.circular(12), onTap: onTap, child: Padding(padding: const EdgeInsets.all(16), child: Row(children: [
    Icon(icon, size: 30), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)), const SizedBox(height: 4), Text(subtitle)])), const SizedBox(width: 8), Column(children: [const Icon(Icons.chevron_left), Text(actionLabel, style: Theme.of(context).textTheme.labelSmall)]),
  ]))));
}

class _Metric {
  const _Metric(this.label, this.value, this.icon, {this.onTap});
  final String label;
  final int value;
  final IconData icon;
  final VoidCallback? onTap;
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.items});
  final List<_Metric> items;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    final width = (constraints.maxWidth - 10) / 2;
    return Wrap(spacing: 10, runSpacing: 10, children: items.map((item) => SizedBox(
      width: width,
      child: Card(child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: item.onTap,
        child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(item.icon), const Spacer(), if (item.onTap != null) const Icon(Icons.chevron_left, size: 18)]),
          const SizedBox(height: 10), Text('${item.value}', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 3), Text(item.label, style: const TextStyle(fontWeight: FontWeight.w700)),
        ])),
      )),
    )).toList(growable: false));
  });
}

class _AdminTile extends StatelessWidget {
  const _AdminTile({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon; final String title; final String subtitle; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(minVerticalPadding: 14, leading: Icon(icon), title: Text(title, style: const TextStyle(fontWeight: FontWeight.w900)), subtitle: Padding(padding: const EdgeInsets.only(top: 4), child: Text(subtitle)), trailing: const Icon(Icons.chevron_left), onTap: onTap));
}

class _TeamMemberCard extends StatelessWidget {
  const _TeamMemberCard(this.member);
  final GeneralManagerTeamMember member;
  @override
  Widget build(BuildContext context) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [CircleAvatar(child: Icon(member.isManager ? Icons.supervisor_account_outlined : Icons.support_agent_outlined)), const SizedBox(width: 10), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(member.name, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16)), Text(member.isManager ? 'مدير دعم' : 'موظف دعم')])), if (member.overdueTasks > 0) Badge(label: Text('${member.overdueTasks} متأخرة'))]),
      const SizedBox(height: 12),
      Wrap(spacing: 7, runSpacing: 7, children: [_MiniChip('مفتوحة', member.openTasks), _MiniChip('مغلقة', member.closedTasks), _MiniChip('عاجلة', member.urgentTasks), _MiniChip('تذاكر', member.tickets), _MiniChip('تحقق', member.verifications), _MiniChip('إعلانات', member.listingReviews), _MiniChip('بلاغات', member.reports)]),
      if (member.averageClaimMinutes != null) ...[const SizedBox(height: 8), Text('متوسط الاستلام: ${member.averageClaimMinutes} دقيقة', style: Theme.of(context).textTheme.bodySmall)],
    ])),
  );
}

class _GovernorateCard extends StatelessWidget {
  const _GovernorateCard({required this.name, required this.total, required this.sale, required this.rent, required this.onTap});
  final String name; final int total; final int sale; final int rent; final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(margin: const EdgeInsets.only(bottom: 8), child: ListTile(
    onTap: onTap, leading: const CircleAvatar(child: Icon(Icons.location_city_outlined)), title: Text(name, style: const TextStyle(fontWeight: FontWeight.w900)), subtitle: Padding(padding: const EdgeInsets.only(top: 6), child: Wrap(spacing: 6, children: [_MiniChip('الكل', total), _MiniChip('بيع', sale), _MiniChip('إيجار', rent)])), trailing: const Icon(Icons.chevron_left),
  ));
}

class _DataRow { const _DataRow(this.label, this.value); final String label; final int value; }
class _DataList extends StatelessWidget {
  const _DataList({required this.rows}); final List<_DataRow> rows;
  @override
  Widget build(BuildContext context) => Card(child: Column(children: List.generate(rows.length, (index) { final row=rows[index]; return Column(children: [ListTile(title: Text(row.label), trailing: Text('${row.value}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17))), if(index!=rows.length-1) const Divider(height: 1)]); })));
}
class _MiniChip extends StatelessWidget { const _MiniChip(this.label,this.value); final String label; final int value; @override Widget build(BuildContext context)=>Chip(visualDensity: VisualDensity.compact,label: Text('$label: $value')); }
class _EmptyPanel extends StatelessWidget { const _EmptyPanel(this.text); final String text; @override Widget build(BuildContext context)=>Card(child: Padding(padding: const EdgeInsets.all(16),child: Text(text))); }

void _openTeam(BuildContext context) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const GeneralManagerTeamScreen()));
void _openMarket(BuildContext context, GeneralManagerInsights data) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _ExecutiveDetailScreen(title: 'السوق العقاري داخل المنصة', icon: Icons.query_stats_outlined, rows: [_DataRow('إجمالي العقارات',data.marketCount('properties_total')),_DataRow('العقارات المنشورة',data.marketCount('published_properties')),_DataRow('للبيع',data.marketCount('published_sale')),_DataRow('للإيجار',data.marketCount('published_rent')),_DataRow('منشورة اليوم',data.marketCount('published_today'))])));
void _openPeople(BuildContext context, GeneralManagerInsights data) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _ExecutiveDetailScreen(title: 'المستخدمون', icon: Icons.people_alt_outlined, rows: [_DataRow('إجمالي المستخدمين',data.overviewCount('users_total')),_DataRow('جدد اليوم',data.todayCount('new_users'))])));
void _openProfessionals(BuildContext context, GeneralManagerInsights data) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _ExecutiveDetailScreen(title: 'الدلالون والمكاتب', icon: Icons.real_estate_agent_outlined, rows: [_DataRow('دلالون موثقون',data.marketCount('approved_brokers')),_DataRow('مكاتب موثقة',data.marketCount('approved_offices')),_DataRow('تحقق مهني معلق',data.marketCount('pending_professional_verifications'))])));
void _openOperations(BuildContext context, GeneralManagerInsights data) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _ExecutiveDetailScreen(title: 'صحة التشغيل', icon: Icons.monitor_heart_outlined, rows: [_DataRow('أعمال دعم مفتوحة',data.overviewCount('open_support_tasks')),_DataRow('متأخرة',data.overviewCount('overdue_support_tasks')),_DataRow('مصعدة',data.overviewCount('escalated_support_tasks')),_DataRow('بلاغات حرجة',data.overviewCount('critical_reports')),_DataRow('إعلانات قيد المراجعة',data.overviewCount('pending_listing_reviews')),_DataRow('طلبات تحقق معلقة',data.overviewCount('pending_verifications'))])));
void _openGovernorate(BuildContext context, Map<String,dynamic> row) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _ExecutiveDetailScreen(title: row['name']?.toString()??'المحافظة', icon: Icons.location_city_outlined, rows: [_DataRow('العقارات المنشورة',_asInt(row['total'])),_DataRow('للبيع',_asInt(row['sale'])),_DataRow('للإيجار',_asInt(row['rent']))])));

class _ExecutiveDetailScreen extends StatelessWidget {
  const _ExecutiveDetailScreen({required this.title, required this.icon, required this.rows});
  final String title; final IconData icon; final List<_DataRow> rows;
  @override
  Widget build(BuildContext context) => Directionality(textDirection: TextDirection.rtl, child: Scaffold(appBar: AppBar(title: Text(title)), body: ListView(padding: const EdgeInsets.all(16), children: [_InfoPanel(icon: icon,title: title,subtitle:'عرض إداري مختصر يساعد على اتخاذ القرار بدون الدخول في مهام التشغيل اليومية.'),const SizedBox(height:12),_DataList(rows:rows)])));
}

int _asInt(dynamic value){if(value is num)return value.toInt();return int.tryParse(value?.toString()??'')??0;}
double? _asDouble(dynamic value){if(value is num)return value.toDouble();return double.tryParse(value?.toString()??'');}
String _propertyTypeLabel(String type)=>switch(type){'apartment'=>'شقة','house'=>'منزل','villa'=>'فيلا','land'=>'أرض','shop'=>'محل','office'=>'مكتب','farm'=>'مزرعة',_=>type.isEmpty?'غير محدد':type};
