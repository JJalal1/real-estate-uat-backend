import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import 'smart_search_assistant.dart';

/// Home and My Account open a new assistant journey without copying Home edits.
class HomeAiSearchEntry extends StatelessWidget {
  const HomeAiSearchEntry(
      {this.location = 'صنعاء',
      this.type,
      this.purpose,
      this.wide = false,
      this.professional = false,
      this.onPressed,
      super.key});

  final String location;
  final String? type;
  final String? purpose;
  final bool wide;
  final bool professional;
  final VoidCallback? onPressed;

  Future<void> _open(BuildContext context) async {
    if (onPressed case final action?) {
      action();
      return;
    }
    if (ModalRoute.of(context)?.isCurrent == false) return;
    if (!professional) {
      await context.push<void>('/smart-search');
      return;
    }
    final choice = await showModalBottomSheet<_HomeAssistantAction>(
      context: context,
      builder: (sheetContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ListTile(
                key: const ValueKey('home-assistant-search'),
                leading: const Icon(Icons.search_rounded),
                title: const Text('بحث ذكي'),
                onTap: () =>
                    Navigator.pop(sheetContext, _HomeAssistantAction.search),
              ),
              ListTile(
                key: const ValueKey('home-assistant-listing'),
                leading: const Icon(Icons.auto_awesome_outlined),
                title: const Text('تجهيز إعلان'),
                onTap: () =>
                    Navigator.pop(sheetContext, _HomeAssistantAction.listing),
              ),
            ]),
          ),
        ),
      ),
    );
    if (choice == null || !context.mounted) return;
    await context.push<void>(choice == _HomeAssistantAction.search
        ? '/smart-search'
        : '/add-property?assistant=1');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.primary;
    if (wide) {
      final radius = BorderRadius.circular(AppRadii.control);
      const ink = Color(0xFF142E47);
      const accent = Color(0xFF007C86);
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Material(
          color: const Color(0xFFE0F4F3),
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            key: const ValueKey('home-smart-search'),
            onTap: () => _open(context),
            borderRadius: radius,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: LayoutBuilder(builder: (context, constraints) {
                final enlarged =
                    MediaQuery.textScalerOf(context).scale(12) > 18;
                final artWidth = (constraints.maxWidth * (enlarged ? .28 : .44))
                    .clamp(0.0, 176.0)
                    .toDouble();
                final title = Text(
                  professional ? 'المساعد الذكي' : 'بحث ذكي',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(color: ink, fontWeight: FontWeight.w700),
                );
                final description = Text(
                  professional
                      ? 'ابحث عن عقار أو جهّز إعلانك'
                      : 'صف العقار اللي تبحث عنه بالنص أو الصوت',
                  style: theme.textTheme.bodySmall?.copyWith(color: ink),
                );
                final content = Row(children: [
                  Expanded(
                    child: enlarged
                        ? title
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              title,
                              const SizedBox(height: 2),
                              description
                            ],
                          ),
                  ),
                  const SizedBox(width: 4),
                  Image.asset('assets/brand/home-smart-assistant.webp',
                      width: artWidth, excludeFromSemantics: true),
                  const Icon(Icons.chevron_left_rounded,
                      color: accent, size: 22),
                ]);
                return enlarged
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          content,
                          const SizedBox(height: 2),
                          description
                        ],
                      )
                    : content;
              }),
            ),
          ),
        ),
      );
    }
    return TextButton.icon(
      key: const ValueKey('home-smart-search'),
      onPressed: () => _open(context),
      style: TextButton.styleFrom(
        foregroundColor: color,
        backgroundColor: color.withValues(alpha: .07),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      icon: const SmartSearchRobotIcon(size: 24),
      label: const Text('بحث ذكي'),
    );
  }
}

enum _HomeAssistantAction { search, listing }
