import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_theme.dart';
import '../../account/data/auth_controller.dart';
import '../data/service_repository.dart';
import '../domain/service_models.dart';

class ServicesScreen extends ConsumerWidget {
  const ServicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: AppTheme.page,
        body: SafeArea(
          child: auth.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, __) => const Center(child: Text('تعذر تحميل الحساب.')),
            data: (user) {
              if (user == null) {
                return _SignedOutServices(onLogin: () => context.push('/auth'));
              }
              final hub = ref.watch(freeServicesHubProvider);
              return hub.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => _HubError(
                  message: friendlyApiError(error),
                  onRetry: () => ref.invalidate(freeServicesHubProvider),
                ),
                data: (model) => RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(freeServicesHubProvider);
                    await ref.read(freeServicesHubProvider.future);
                  },
                  child: _FreeServicesHub(model: model),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _FreeServicesHub extends StatelessWidget {
  const _FreeServicesHub({required this.model});

  final FreeServicesHubModel model;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        _hero(),
        const SizedBox(height: 24),
        const _SectionTitle('الخدمات السريعة', icon: Icons.bolt_rounded),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          childAspectRatio: 1.45,
          children: [
            _QuickCard(
              title: 'أضف عقار',
              subtitle: model.can('create_listing')
                  ? 'أنشئ إعلانًا جديدًا'
                  : 'يتطلب حسابًا مهنيًا موثقًا',
              icon: Icons.add_home_work_outlined,
              badge: model.requiresVerification('create_listing')
                  ? 'يتطلب التحقق'
                  : 'مجاني',
              onTap: () => _open(context, 'create_listing'),
            ),
            _QuickCard(
              title: 'اطلب عقار',
              subtitle: 'أنشئ طلبًا بمواصفاتك',
              icon: Icons.manage_search_rounded,
              badge: _badge('property_requests'),
              onTap: () => _open(context, 'property_requests'),
            ),
            _QuickCard(
              title: 'إعلاناتي',
              subtitle: 'تابع إعلاناتك وحالاتها',
              icon: Icons.inventory_2_outlined,
              badge: 'مجاني',
              onTap: () => _open(context, 'my_listings'),
            ),
            _QuickCard(
              title: 'قيّم عقارك',
              subtitle: 'تقدير استرشادي من بيانات المنصة',
              icon: Icons.analytics_outlined,
              badge: _badge('property_valuation'),
              onTap: () => _open(context, 'property_valuation'),
            ),
          ],
        ),
        const SizedBox(height: 26),
        const _SectionTitle('الخدمات العقارية'),
        const SizedBox(height: 10),
        _ServiceTile(
          title: 'طلبات العقار',
          subtitle: 'أنشئ طلباتك وتابع حالتها',
          icon: Icons.search_rounded,
          badge: _badge('property_requests'),
          onTap: () => _open(context, 'property_requests'),
        ),
        if (model.can('rental_contracts'))
          _ServiceTile(
            title: 'عقود الإيجار',
            subtitle: 'عقود مرتبطة بعقارات وأطراف حقيقيين',
            icon: Icons.description_outlined,
            badge: _badge('rental_contracts'),
            onTap: () => _open(context, 'rental_contracts'),
          ),
        _ServiceTile(
          title: 'مؤشرات الأسعار',
          subtitle: 'بيانات من الإعلانات المنشورة والمعتمدة',
          icon: Icons.bar_chart_rounded,
          badge: _badge('price_indicators'),
          onTap: () => _open(context, 'price_indicators'),
        ),
        _ServiceTile(
          title: 'تقييم العقار',
          subtitle: 'مقارنة استرشادية بعقارات مشابهة',
          icon: Icons.home_work_outlined,
          badge: _badge('property_valuation'),
          onTap: () => _open(context, 'property_valuation'),
        ),
        if (model.can('view_researcher_requests'))
          _ServiceTile(
            title: 'طلبات الباحثين',
            subtitle: 'طابق طلبات الباحثين بعقاراتك المنشورة',
            icon: Icons.person_search_outlined,
            badge: _badge('researcher_requests'),
            onTap: () => _open(context, 'researcher_requests'),
          ),
        const SizedBox(height: 24),
        const _SectionTitle('معلومات وأدوات'),
        const SizedBox(height: 10),
        _ServiceTile(
          title: 'الدليل العقاري',
          subtitle: 'مقالات عملية للشراء والبيع والإيجار بأمان',
          icon: Icons.menu_book_outlined,
          badge: _badge('real_estate_guide'),
          onTap: () => _open(context, 'real_estate_guide'),
        ),
        _ServiceTile(
          title: 'المستندات القانونية',
          subtitle: 'نماذج وإرشادات عقارية بصيغة إرشادية',
          icon: Icons.article_outlined,
          badge: _badge('legal_library'),
          onTap: () => _open(context, 'legal_library'),
        ),
      ],
    );
  }

  Widget _hero() {
    final verifiedText = model.verifiedProfessional
        ? 'موثق للخدمات المهنية'
        : model.accountType == 'basic'
            ? 'الخدمات الأساسية متاحة مجانًا'
            : 'بعض الخدمات المهنية تتطلب اكتمال التحقق';
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [AppTheme.brand, AppTheme.brandStrong],
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'الخدمات العقارية',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  'مجانية بالكامل',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${model.accountTypeLabel} • $verifiedText',
            style: const TextStyle(
              color: Colors.white70,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  String _badge(String code) => model.isAvailable(code) ? 'مجاني' : 'قريبًا';

  void _open(BuildContext context, String code) {
    if (code == 'create_listing') {
      if (model.can('create_listing') && model.isAvailable(code)) {
        context.push('/add-property');
      } else {
        context.push('/account-verification');
      }
      return;
    }
    if (code == 'my_listings') {
      context.push('/my-listings');
      return;
    }
    final labels = <String, String>{
      'property_requests': 'طلبات العقار',
      'researcher_requests': 'طلبات الباحثين',
      'rental_contracts': 'عقود الإيجار',
      'price_indicators': 'مؤشرات الأسعار',
      'property_valuation': 'تقييم العقار',
      'real_estate_guide': 'الدليل العقاري',
      'legal_library': 'المستندات القانونية',
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '${labels[code] ?? 'الخدمة'} ضمن التطوير الحالي وستُفعّل بعد اكتمال منطقها في الـBackend.',
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {this.icon});
  final String title;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
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
}

class _QuickCard extends StatelessWidget {
  const _QuickCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.badge,
    required this.onTap,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final String badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppTheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppTheme.outlineSoft.withValues(alpha: 0.55)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: AppTheme.brandSoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(icon, color: AppTheme.brandStrong),
                  ),
                  const Spacer(),
                  _Badge(text: badge),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: AppTheme.textStrong,
                  fontSize: 15,
                ),
              ),
              Text(
                subtitle,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppTheme.textMuted,
                  fontSize: 11.5,
                  height: 1.25,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceTile extends StatelessWidget {
  const _ServiceTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.badge,
    required this.onTap,
  });
  final String title;
  final String subtitle;
  final IconData icon;
  final String badge;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
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
              border: Border.all(color: AppTheme.outlineSoft.withValues(alpha: 0.55)),
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
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: const TextStyle(
                                color: AppTheme.textStrong,
                                fontSize: 16,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          _Badge(text: badge),
                        ],
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
                const SizedBox(width: 4),
                const Icon(Icons.chevron_left_rounded, color: AppTheme.outlineSoft),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.brandSoft,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: AppTheme.brandStrong,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SignedOutServices extends StatelessWidget {
  const _SignedOutServices({required this.onLogin});
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.apps_outlined, size: 58, color: AppTheme.brandStrong),
            const SizedBox(height: 12),
            const Text('سجّل الدخول لعرض الخدمات المناسبة لحسابك.'),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: onLogin,
              icon: const Icon(Icons.login),
              label: const Text('تسجيل الدخول'),
            ),
          ],
        ),
      ),
    );
  }
}

class _HubError extends StatelessWidget {
  const _HubError({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 54),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('إعادة المحاولة'),
            ),
          ],
        ),
      ),
    );
  }
}
