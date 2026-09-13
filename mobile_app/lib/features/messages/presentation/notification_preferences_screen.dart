import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_components.dart';
import '../data/notification_preference_repository.dart';

class NotificationPreferencesScreen extends ConsumerStatefulWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  ConsumerState<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends ConsumerState<NotificationPreferencesScreen> {
  NotificationPreferences? _draft;
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationPreferencesProvider);
    final loaded = state.asData?.value;
    _draft ??= loaded;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: const AppAppBar(title: 'تفضيلات الإشعارات'),
        body: state.when(
          loading: () => const _PreferenceSkeleton(),
          error: (error, _) => AppErrorState(
            message: friendlyApiError(error),
            onRetry: () => ref.invalidate(notificationPreferencesProvider),
          ),
          data: (serverValue) {
            final value = _draft ?? serverValue;
            return ListView(
              padding: const EdgeInsetsDirectional.fromSTEB(
                AppLayout.compactPageGutter,
                AppSpacing.s16,
                AppLayout.compactPageGutter,
                AppSpacing.s40,
              ),
              children: [
                const AppInlineMessage(
                  title: 'الإشعارات المهمة تبقى شغالة',
                  message:
                      'رسائل الأمان، التحقق من الحساب، وردود الدعم الضرورية لا يمكن إيقافها حتى ما يفوتك شيء مهم.',
                  tone: AppStatusTone.info,
                  icon: Icons.shield_outlined,
                ),
                const SizedBox(height: AppSpacing.s16),
                _PreferenceCard(
                  icon: Icons.chat_bubble_outline,
                  title: 'الرسائل',
                  subtitle: 'رسالة جديدة في محادثة عقارية.',
                  value: value.messages,
                  onChanged: (enabled) => _change(
                    value.copyWith(messages: enabled),
                  ),
                ),
                const SizedBox(height: AppSpacing.s10),
                _PreferenceCard(
                  icon: Icons.calendar_month_outlined,
                  title: 'المعاينات',
                  subtitle: 'تأكيد، تغيير، رفض أو تحديث موعد المعاينة.',
                  value: value.viewings,
                  onChanged: (enabled) => _change(
                    value.copyWith(viewings: enabled),
                  ),
                ),
                const SizedBox(height: AppSpacing.s10),
                _PreferenceCard(
                  icon: Icons.handshake_outlined,
                  title: 'الاتفاقات والعقود',
                  subtitle: 'نسخة اتفاق جديدة، قبول طرف، أو تحديث عقد الإيجار.',
                  value: value.agreements,
                  onChanged: (enabled) => _change(
                    value.copyWith(agreements: enabled),
                  ),
                ),
                const SizedBox(height: AppSpacing.s10),
                _PreferenceCard(
                  icon: Icons.home_work_outlined,
                  title: 'نشاط إعلاناتي',
                  subtitle: 'تحديثات ومراجعات مرتبطة بإعلاناتك العقارية.',
                  value: value.listingActivity,
                  onChanged: (enabled) => _change(
                    value.copyWith(listingActivity: enabled),
                  ),
                ),
                const SizedBox(height: AppSpacing.s10),
                _PreferenceCard(
                  icon: Icons.saved_search_outlined,
                  title: 'البحث والمفضلة',
                  subtitle:
                      'عقار جديد يطابق بحثًا محفوظًا أو تغيّر سعر عقار في المفضلة.',
                  value: value.discoveryAlerts,
                  onChanged: (enabled) => _change(
                    value.copyWith(discoveryAlerts: enabled),
                  ),
                ),
                const SizedBox(height: AppSpacing.s10),
                _PreferenceCard(
                  icon: Icons.design_services_outlined,
                  title: 'الخدمات',
                  subtitle: 'تحديثات الخدمات الاختيارية داخل التطبيق.',
                  value: value.services,
                  onChanged: (enabled) => _change(
                    value.copyWith(services: enabled),
                  ),
                ),
                const SizedBox(height: AppSpacing.s20),
                AppButton(
                  label: _saving ? 'جارٍ الحفظ...' : 'حفظ التفضيلات',
                  icon: Icons.check_rounded,
                  loading: _saving,
                  onPressed: _saving ? null : _save,
                  expand: true,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _change(NotificationPreferences value) {
    setState(() => _draft = value);
  }

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null || _saving) return;
    setState(() => _saving = true);
    try {
      final saved = await ref
          .read(notificationPreferenceRepositoryProvider)
          .update(draft.toApi());
      if (!mounted) return;
      setState(() => _draft = saved);
      ref.invalidate(notificationPreferencesProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ تفضيلات الإشعارات.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyApiError(error))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _PreferenceCard extends StatelessWidget {
  const _PreferenceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppSurface(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: AppSpacing.s12,
        vertical: AppSpacing.s8,
      ),
      child: SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        value: value,
        onChanged: onChanged,
        secondary: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: value ? scheme.primaryContainer : scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(AppRadii.control),
          ),
          child: Icon(
            icon,
            color: value ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ),
        title: Text(
          title,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        subtitle: Text(subtitle),
      ),
    );
  }
}

class _PreferenceSkeleton extends StatelessWidget {
  const _PreferenceSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsetsDirectional.all(AppLayout.compactPageGutter),
      itemCount: 6,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.s10),
      itemBuilder: (_, __) => const AppSkeleton(
        height: 88,
        radius: AppRadii.card,
      ),
    );
  }
}
