import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_theme.dart';
import '../../account/data/auth_controller.dart';
import '../data/service_repository.dart';
import '../domain/service_models.dart';

final _catalogProvider = FutureProvider.autoDispose(
    (ref) => ref.watch(serviceRepositoryProvider).catalog());
final _ordersProvider = FutureProvider.autoDispose(
    (ref) => ref.watch(serviceRepositoryProvider).mineOrders());
final _entitlementsProvider = FutureProvider.autoDispose(
    (ref) => ref.watch(serviceRepositoryProvider).mineEntitlements());
final _adminOffersProvider = FutureProvider.autoDispose(
    (ref) => ref.watch(serviceRepositoryProvider).adminOffers());
final _adminOrdersProvider = FutureProvider.autoDispose(
    (ref) => ref.watch(serviceRepositoryProvider).adminOrders());

class ServicesScreen extends ConsumerStatefulWidget {
  const ServicesScreen({super.key});

  @override
  ConsumerState<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends ConsumerState<ServicesScreen> {
  String? _activePanel;

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    return auth.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, __) =>
          const Scaffold(body: Center(child: Text('تعذر تحميل الحساب.'))),
      data: (user) {
        if (user == null) {
          return const Scaffold(body: Center(child: Text('يجب تسجيل الدخول.')));
        }
        final canServices =
            user.isPlatformOwner || user.hasPermission('services.manage');
        final canPayments =
            user.isPlatformOwner || user.hasPermission('payments.manage');
        final panel = _activePanel;
        late final Widget body;
        String? panelTitle;
        if (panel == 'catalog') {
          panelTitle = 'خدمات التسويق والترقيات';
          body = _catalog();
        } else if (panel == 'orders') {
          panelTitle = 'طلباتي';
          body = _orders();
        } else if (panel == 'entitlements') {
          panelTitle = 'خدماتي';
          body = _entitlements();
        } else if (panel == 'adminOffers' && canServices) {
          panelTitle = 'إدارة الخدمات';
          body = _adminOffers();
        } else if (panel == 'adminOrders' && canPayments) {
          panelTitle = 'المدفوعات';
          body = _adminOrders();
        } else {
          body = _serviceHub(
            canManageServices: canServices,
            canManagePayments: canPayments,
          );
        }
        return Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            backgroundColor: AppTheme.page,
            appBar: panelTitle == null
                ? null
                : AppBar(
                    title: Text(panelTitle),
                    leading: IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => setState(() => _activePanel = null),
                    ),
                  ),
            body: SafeArea(child: body),
          ),
        );
      },
    );
  }

  Widget _serviceHub({
    required bool canManageServices,
    required bool canManagePayments,
  }) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        _sectionTitle('خدمات سريعة', icon: Icons.bolt_rounded),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          childAspectRatio: 0.78,
          children: [
            _quickServiceCard(
              title: 'قيّم عقارك',
              subtitle: 'اعرف قيمة عقارك',
              icon: Icons.sell_outlined,
              onTap: () => _showNotConnectedYet('تقييم العقار'),
            ),
            _quickServiceCard(
              title: 'احجز معاينة',
              subtitle: 'حدد موعد الزيارة',
              icon: Icons.calendar_month_outlined,
              onTap: () => context.push('/bookings'),
            ),
            _quickServiceCard(
              title: 'اطلب عقار',
              subtitle: 'نبحث لك مجاناً',
              icon: Icons.manage_search_rounded,
              onTap: () => _showNotConnectedYet('طلب عقار بمواصفاتك'),
            ),
            _quickServiceCard(
              title: 'أضف عقارك',
              subtitle: 'انشر عقارك الآن',
              icon: Icons.add_circle_outline_rounded,
              onTap: () => context.push('/add-property'),
            ),
          ],
        ),
        const SizedBox(height: 26),
        _sectionTitle('الخدمات الرئيسية'),
        const SizedBox(height: 10),
        _serviceTile(
          title: 'إعلانات اليوم',
          subtitle: 'عقارات للبيع والإيجار المضافة حديثاً',
          icon: Icons.home_work_outlined,
          onTap: () => context.go('/'),
        ),
        _serviceTile(
          title: 'عقود الإيجار',
          subtitle: 'توثيق وإدارة عقود الإيجار',
          icon: Icons.description_outlined,
          onTap: () => _showNotConnectedYet('عقود الإيجار'),
        ),
        _serviceTile(
          title: 'طلبات البحث',
          subtitle: 'أنشئ طلب عقار بمواصفاتك',
          icon: Icons.search_rounded,
          onTap: () => _showNotConnectedYet('طلبات البحث'),
        ),
        _serviceTile(
          title: 'خدمات التسويق الحصري',
          subtitle: 'سوّق عقارك لآلاف العملاء',
          icon: Icons.campaign_outlined,
          onTap: () => _selectPanel('catalog'),
        ),
        _serviceTile(
          title: 'متوسط الأسعار',
          subtitle: 'استعرض متوسط أسعار العقارات',
          icon: Icons.bar_chart_rounded,
          onTap: () => _showNotConnectedYet('متوسط الأسعار'),
        ),
        _serviceTile(
          title: 'الصفقات العقارية',
          subtitle: 'اطلع على الصفقات الأخيرة',
          icon: Icons.receipt_long_outlined,
          onTap: () => _showNotConnectedYet('الصفقات العقارية'),
        ),
        const SizedBox(height: 24),
        _sectionTitle('تطبيق'),
        const SizedBox(height: 10),
        _serviceTile(
          title: 'المدونة',
          subtitle: 'مقالات ونصائح عقارية',
          icon: Icons.menu_book_outlined,
          onTap: () => _showNotConnectedYet('المدونة'),
        ),
        _serviceTile(
          title: 'المستندات القانونية',
          subtitle: 'نماذج ومستندات جاهزة',
          icon: Icons.article_outlined,
          onTap: () => _showNotConnectedYet('المستندات القانونية'),
        ),
        const SizedBox(height: 24),
        _sectionTitle('حساب الخدمات'),
        const SizedBox(height: 10),
        _serviceTile(
          title: 'طلباتي',
          subtitle: 'تابع طلبات الخدمات وحالة الدفع',
          icon: Icons.shopping_bag_outlined,
          onTap: () => _selectPanel('orders'),
        ),
        _serviceTile(
          title: 'خدماتي',
          subtitle: 'الخدمات المفعلة والسابقة',
          icon: Icons.verified_outlined,
          onTap: () => _selectPanel('entitlements'),
        ),
        if (canManageServices) ...[
          const SizedBox(height: 18),
          _sectionTitle('إدارة الخدمات'),
          const SizedBox(height: 10),
          _serviceTile(
            title: 'إدارة الخدمات والترقيات',
            subtitle: 'الأسعار والتفعيل والمدة',
            icon: Icons.settings_suggest_outlined,
            onTap: () => _selectPanel('adminOffers'),
          ),
        ],
        if (canManagePayments)
          _serviceTile(
            title: 'المدفوعات والتسويات',
            subtitle: 'متابعة التسوية والاسترداد',
            icon: Icons.payments_outlined,
            onTap: () => _selectPanel('adminOrders'),
          ),
      ],
    );
  }

  Widget _sectionTitle(String title, {IconData? icon}) {
    return Row(
      children: [
        if (icon != null) ...[
          Icon(icon, color: AppTheme.brand, size: 24),
          const SizedBox(width: 6),
        ] else ...[
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: AppTheme.brand,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
        ],
        Text(
          title,
          style: const TextStyle(
            color: AppTheme.textStrong,
            fontSize: 19,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _quickServiceCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border:
                Border.all(color: AppTheme.outlineSoft.withValues(alpha: 0.55)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.035),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.brandSoft,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, color: AppTheme.brandStrong, size: 27),
              ),
              const SizedBox(height: 9),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.textStrong,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10.5,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _serviceTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 74),
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: AppTheme.outlineSoft.withValues(alpha: 0.55)),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppTheme.brandSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: AppTheme.brandStrong, size: 28),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          color: AppTheme.textStrong,
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          color: AppTheme.textMuted,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_left_rounded,
                  color: AppTheme.outlineSoft,
                  size: 28,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showNotConnectedYet(String title) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content:
            Text('$title: الواجهة جاهزة وسيتم ربط الخدمة عند تجهيز منطقها.'),
      ),
    );
  }

  void _selectPanel(String panel) {
    setState(() => _activePanel = panel);
  }

  Widget _catalog() {
    final state = ref.watch(_catalogProvider);
    return state.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) =>
          _error(error, () => ref.invalidate(_catalogProvider)),
      data: (rows) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_catalogProvider);
          await ref.read(_catalogProvider.future);
        },
        child: rows.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                    SizedBox(height: 150),
                    Icon(Icons.workspace_premium_outlined, size: 56),
                    SizedBox(height: 12),
                    Center(
                        child: Padding(
                            padding: EdgeInsets.all(20),
                            child: Text(
                                'لا توجد خدمات مفعلة حالياً. المسؤول يحدد السعر والعملة ثم يفعّل القالب.',
                                textAlign: TextAlign.center)))
                  ])
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, index) {
                  final offer = rows[index];
                  return Card(
                      child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(offer.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w900,
                                        fontSize: 17)),
                                if (offer.description != null) ...[
                                  const SizedBox(height: 5),
                                  Text(offer.description!)
                                ],
                                const SizedBox(height: 7),
                                Text(
                                    '${offer.targetLabel} • ${offer.durationDays ?? 0} يوم • ${offer.priceAmount} ${offer.currency}'),
                                const SizedBox(height: 10),
                                FilledButton.icon(
                                    onPressed: () => _order(offer),
                                    icon: const Icon(
                                        Icons.shopping_cart_checkout),
                                    label: const Text('طلب الخدمة')),
                              ])));
                }),
      ),
    );
  }

  Widget _orders() {
    final state = ref.watch(_ordersProvider);
    return state.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _error(error, () => ref.invalidate(_ordersProvider)),
      data: (rows) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(_ordersProvider);
            await ref.read(_ordersProvider.future);
          },
          child: _orderList(rows, admin: false)),
    );
  }

  Widget _entitlements() {
    final state = ref.watch(_entitlementsProvider);
    return state.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) =>
          _error(error, () => ref.invalidate(_entitlementsProvider)),
      data: (rows) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_entitlementsProvider);
          await ref.read(_entitlementsProvider.future);
        },
        child: rows.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: const [
                    SizedBox(height: 150),
                    Icon(Icons.verified_outlined, size: 56),
                    SizedBox(height: 10),
                    Center(child: Text('لا توجد خدمات مفعلة أو سابقة.'))
                  ])
            : ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, index) {
                  final item = rows[index];
                  final end = item.endsAt?.toLocal();
                  return Card(
                      child: ListTile(
                          leading: Icon(item.isActive
                              ? Icons.verified
                              : Icons.block_outlined),
                          title: Text(item.serviceName,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800)),
                          subtitle: Text(
                              '${item.targetTitle ?? 'الحساب'}${end == null ? '' : '\nحتى ${end.year}/${end.month}/${end.day}'}'),
                          trailing: Chip(
                              label: Text(item.isActive
                                  ? 'فعالة'
                                  : item.status == 'revoked'
                                      ? 'مبطلة'
                                      : 'منتهية'))));
                },
              ),
      ),
    );
  }

  Widget _adminOffers() {
    final state = ref.watch(_adminOffersProvider);
    return state.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) =>
          _error(error, () => ref.invalidate(_adminOffersProvider)),
      data: (rows) => RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_adminOffersProvider);
          await ref.read(_adminOffersProvider.future);
        },
        child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: rows.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, index) {
              final offer = rows[index];
              return Card(
                  child: ListTile(
                      leading: Icon(
                          offer.isActive ? Icons.toggle_on : Icons.toggle_off),
                      title: Text(offer.name,
                          style: const TextStyle(fontWeight: FontWeight.w800)),
                      subtitle: Text(
                          '${offer.code}\n${offer.priceAmount} ${offer.currency} • ${offer.durationDays ?? 0} يوم'),
                      isThreeLine: true,
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: () => _editOffer(offer)));
            }),
      ),
    );
  }

  Widget _adminOrders() {
    final state = ref.watch(_adminOrdersProvider);
    return state.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) =>
          _error(error, () => ref.invalidate(_adminOrdersProvider)),
      data: (rows) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(_adminOrdersProvider);
            await ref.read(_adminOrdersProvider.future);
          },
          child: _orderList(rows, admin: true)),
    );
  }

  Widget _orderList(List<ServiceOrderModel> rows, {required bool admin}) {
    if (rows.isEmpty) {
      return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 150),
            Icon(Icons.receipt_long_outlined, size: 56),
            SizedBox(height: 10),
            Center(child: Text('لا توجد أوامر خدمة.'))
          ]);
    }
    return ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (_, index) {
          final order = rows[index];
          return Card(
              child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                              child: Text(order.serviceName,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900))),
                          Chip(label: Text(order.statusLabel))
                        ]),
                        Text(order.targetTitle ?? 'الحساب'),
                        const SizedBox(height: 4),
                        Text(
                            '${order.amount} ${order.currency} • ${order.reference}'),
                        if (order.paymentReference != null) ...[
                          const SizedBox(height: 4),
                          Text('مرجع الدفع: ${order.paymentReference}')
                        ],
                        if (!admin && order.canCancel) ...[
                          const SizedBox(height: 9),
                          OutlinedButton.icon(
                              onPressed: () => _cancel(order),
                              icon: const Icon(Icons.cancel_outlined),
                              label: const Text('إلغاء الطلب'))
                        ],
                        if (admin && order.canSettle) ...[
                          const SizedBox(height: 9),
                          FilledButton.tonalIcon(
                              onPressed: () => _settle(order),
                              icon: const Icon(Icons.price_check_outlined),
                              label: const Text('تسجيل دفعة مؤكدة'))
                        ],
                        if (admin && order.canRefund) ...[
                          const SizedBox(height: 9),
                          OutlinedButton.icon(
                              onPressed: () => _refund(order),
                              icon: const Icon(Icons.undo_outlined),
                              label: const Text('تسجيل استرداد'))
                        ],
                      ])));
        });
  }

  Widget _error(Object error, VoidCallback retry) => Center(
      child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(friendlyApiError(error), textAlign: TextAlign.center),
            const SizedBox(height: 10),
            OutlinedButton.icon(
                onPressed: retry,
                icon: const Icon(Icons.refresh),
                label: const Text('إعادة المحاولة'))
          ])));

  Future<void> _order(ServiceOfferingModel offer) async {
    try {
      int? targetId;
      if (offer.targetType == 'property') {
        final listings = await ref.read(serviceRepositoryProvider).myListings();
        if (!mounted) {
          return;
        }
        if (listings.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('لا يوجد إعلان منشور ومعتمد مؤهل لهذه الخدمة.')));
          return;
        }
        targetId = await showModalBottomSheet<int>(
            context: context,
            builder: (sheetContext) => SafeArea(
                    child: ListView(shrinkWrap: true, children: [
                  const ListTile(
                      title: Text('اختر الإعلان',
                          style: TextStyle(fontWeight: FontWeight.w900))),
                  ...listings.map((item) => ListTile(
                      title: Text(item.title),
                      trailing: const Icon(Icons.chevron_left),
                      onTap: () => Navigator.pop(sheetContext, item.id)))
                ])));
        if (targetId == null) {
          return;
        }
      }
      if (!mounted) {
        return;
      }
      final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
                  title: const Text('تأكيد طلب الخدمة'),
                  content: Text(
                      '${offer.name}\n${offer.priceAmount} ${offer.currency}\nلا يتم خصم بطاقة داخل التطبيق؛ الطلب سيبقى معلقاً حتى تسجيل دفعة مؤكدة.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('رجوع')),
                    FilledButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text('إنشاء الطلب'))
                  ]));
      if (confirmed != true) {
        return;
      }
      await ref
          .read(serviceRepositoryProvider)
          .createOrder(offer.id, targetId: targetId);
      ref.invalidate(_ordersProvider);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تم إنشاء طلب الخدمة وبانتظار تأكيد الدفع.')));
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    }
  }

  Future<void> _cancel(ServiceOrderModel order) async {
    try {
      await ref.read(serviceRepositoryProvider).cancelOrder(order.id);
      ref.invalidate(_ordersProvider);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    }
  }

  Future<void> _editOffer(ServiceOfferingModel offer) async {
    final price = TextEditingController(text: offer.priceAmount);
    final currency = TextEditingController(text: offer.currency);
    final days =
        TextEditingController(text: offer.durationDays?.toString() ?? '');
    bool active = offer.isActive;
    final payload = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
            builder: (context, setLocal) => AlertDialog(
                    title: Text(offer.name),
                    content: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      TextField(
                          controller: price,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration:
                              const InputDecoration(labelText: 'السعر')),
                      TextField(
                          controller: currency,
                          maxLength: 3,
                          decoration: const InputDecoration(
                              labelText: 'العملة (3 أحرف)')),
                      TextField(
                          controller: days,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'المدة بالأيام')),
                      SwitchListTile(
                          value: active,
                          onChanged: (value) => setLocal(() => active = value),
                          title: const Text('مفعلة للمستخدمين'))
                    ])),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(dialogContext),
                          child: const Text('إلغاء')),
                      FilledButton(
                          onPressed: () => Navigator.pop(dialogContext, {
                                'price': price.text.trim(),
                                'currency': currency.text.trim(),
                                'days': int.tryParse(days.text.trim()),
                                'active': active
                              }),
                          child: const Text('حفظ'))
                    ])));
    price.dispose();
    currency.dispose();
    days.dispose();
    if (payload == null) {
      return;
    }
    try {
      await ref.read(serviceRepositoryProvider).updateOffer(offer.id,
          priceAmount: payload['price'] as String,
          currency: payload['currency'] as String,
          durationDays: payload['days'] as int?,
          isActive: payload['active'] as bool);
      ref.invalidate(_adminOffersProvider);
      ref.invalidate(_catalogProvider);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    }
  }

  Future<void> _settle(ServiceOrderModel order) async {
    final reference =
        await _textDialog('تسجيل دفعة مؤكدة', 'مرجع خارجي/تحويل مؤكد');
    if (reference == null) {
      return;
    }
    try {
      await ref.read(serviceRepositoryProvider).settle(order.id, reference);
      ref.invalidate(_adminOrdersProvider);
      ref.invalidate(_ordersProvider);
      ref.invalidate(_entitlementsProvider);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    }
  }

  Future<void> _refund(ServiceOrderModel order) async {
    final reason = await _textDialog('تسجيل استرداد', 'سبب الاسترداد');
    if (reason == null) {
      return;
    }
    try {
      await ref.read(serviceRepositoryProvider).refund(order.id, reason);
      ref.invalidate(_adminOrdersProvider);
      ref.invalidate(_ordersProvider);
      ref.invalidate(_entitlementsProvider);
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    }
  }

  Future<String?> _textDialog(String title, String label) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
                title: Text(title),
                content: TextField(
                    controller: controller,
                    maxLength: 1500,
                    minLines: 1,
                    maxLines: 4,
                    decoration: InputDecoration(labelText: label)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('إلغاء')),
                  FilledButton(
                      onPressed: () =>
                          Navigator.pop(dialogContext, controller.text.trim()),
                      child: const Text('حفظ'))
                ]));
    controller.dispose();
    if (value == null || value.length < 3) {
      return null;
    }
    return value;
  }
}
