import 'package:flutter/material.dart';
import '../../../core/widgets/ebroker_widgets.dart';

Future<bool?> showListingCreationMenu(BuildContext context) => showGeneralDialog<bool>(
  context: context, barrierDismissible: true, barrierLabel: 'إغلاق خيارات الإعلان',
  barrierColor: const Color(0xFF192F48).withValues(alpha: .24),
  transitionDuration: MediaQuery.disableAnimationsOf(context) ? Duration.zero : const Duration(milliseconds: 220),
  pageBuilder: (context, _, __) => Directionality(textDirection: TextDirection.rtl, child: SafeArea(
    child: Align(alignment: Alignment.bottomCenter, child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 104),
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 420), child: Material(
        color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(28), elevation: 12,
        child: SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(22), child: Column(
          mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [Expanded(child: Text('إعلانك يبدأ هنا', style: Theme.of(context).textTheme.titleLarge)),
              IconButton(tooltip: 'إغلاق خيارات الإعلان', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded))]),
            Text('اختر الطريقة التي تناسبك', style: Theme.of(context).textTheme.bodySmall), const SizedBox(height: 18),
            _CreationOption(key: const ValueKey('create-listing-ai'), title: 'جهّز بالذكاء الاصطناعي',
              subtitle: 'صف عقارك كتابةً أو صوتًا، وراجع إعلانًا جاهزًا ببياناتك.', icon: Icons.auto_awesome_rounded,
              primary: true, onTap: () => Navigator.pop(context, true)),
            const SizedBox(height: 10),
            _CreationOption(key: const ValueKey('create-listing-manual'), title: 'أدخل البيانات',
              subtitle: 'أضف تفاصيل العقار خطوة بخطوة.', icon: Icons.edit_note_rounded,
              onTap: () => Navigator.pop(context, false)),
          ]))))))))),
  transitionBuilder: (context, animation, _, child) => FadeTransition(opacity: animation,
    child: SlideTransition(position: Tween(begin: const Offset(0, .06), end: Offset.zero).animate(
      CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)), child: child)),
);

class _CreationOption extends StatelessWidget {
  const _CreationOption({required this.title, required this.subtitle, required this.icon, required this.onTap, this.primary = false, super.key});
  final String title, subtitle;
  final IconData icon;
  final bool primary;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = primary ? Colors.white : scheme.onSurface;
    return Material(color: primary ? scheme.secondary : scheme.surfaceContainerLow, borderRadius: BorderRadius.circular(20),
      child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(20), child: Padding(padding: const EdgeInsets.all(16),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(
            color: primary ? Colors.white.withValues(alpha: .12) : scheme.primaryContainer, borderRadius: BorderRadius.circular(14)),
            child: EbrokerIcon(icon, size: 23, color: primary ? const Color(0xFFA6E3D7) : scheme.primary)), const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(color: foreground)), const SizedBox(height: 5),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: primary ? const Color(0xFFD9E6F1) : scheme.onSurfaceVariant)),
          ])),
        ]))));
  }
}
