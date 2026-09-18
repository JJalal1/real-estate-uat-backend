import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/config/v2_package.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_components.dart';
import '../../account/data/auth_controller.dart';

class P02HomeScreen extends ConsumerWidget {
  const P02HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).asData?.value;
    final scheme = Theme.of(context).colorScheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('عقارات حولك'),
          actions: [
            IconButton(
              tooltip: 'الدعم الفني',
              onPressed: () => context.push('/support-info'),
              icon: const Icon(Icons.headset_mic_outlined),
            ),
            const SizedBox(width: 6),
          ],
        ),
        body: ListView(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 32),
          children: [
            Text(
              user == null
                  ? 'ابحث عن عقارك بسهولة'
                  : 'أهلاً ${_firstName(user.name)}',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 6),
            Text(
              'حدد ما تريد، اختر المكان، وشاهد النتائج.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsetsDirectional.all(18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [scheme.primary, scheme.secondary],
                  begin: AlignmentDirectional.topStart,
                  end: AlignmentDirectional.bottomEnd,
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'وين تريد العقار؟',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          color: Colors.white,
                        ),
                  ),
                  const SizedBox(height: 12),
                  Material(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(16),
                      onTap: () => context.push('/property-market'),
                      child: Padding(
                        padding: const EdgeInsetsDirectional.symmetric(
                          horizontal: 14,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.search_rounded, color: scheme.secondary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'ابحث بالحي أو المنطقة',
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                            ),
                            Icon(
                              Icons.arrow_back_ios_new_rounded,
                              size: 16,
                              color: scheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _QuickIntent(
                          icon: Icons.sell_outlined,
                          label: 'شراء',
                          onTap: () => context.push('/property-market'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _QuickIntent(
                          icon: Icons.key_outlined,
                          label: 'إيجار',
                          onTap: () => context.push('/property-market'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Row(
              children: [
                Expanded(
                  child: _MiniAction(
                    icon: Icons.favorite_border_rounded,
                    label: 'المفضلة',
                    onTap: () => context.push('/favorites'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MiniAction(
                    icon: Icons.manage_search_outlined,
                    label: 'طلب عقار',
                    onTap: () => context.push('/property-requests'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _MiniAction(
                    icon: Icons.map_outlined,
                    label: 'الخريطة',
                    onTap: () => context.push('/property-market'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            AppInlineMessage(
              title: 'رحلة قصيرة',
              message: 'اختيار العملية ← تحديد المكان ← مشاهدة العقارات.',
              tone: AppStatusTone.info,
            ),
            const SizedBox(height: 18),
            Align(
              alignment: AlignmentDirectional.center,
              child: Text(
                V2Package.displayLabel,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _firstName(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    return parts.isEmpty || parts.first.isEmpty ? name : parts.first;
  }
}

class _QuickIntent extends StatelessWidget {
  const _QuickIntent({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                label,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: Colors.white,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MiniAction extends StatelessWidget {
  const _MiniAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsetsDirectional.symmetric(vertical: 14),
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Column(
            children: [
              Icon(icon, color: scheme.secondary, size: 24),
              const SizedBox(height: 6),
              Text(label, style: Theme.of(context).textTheme.labelMedium),
            ],
          ),
        ),
      ),
    );
  }
}
