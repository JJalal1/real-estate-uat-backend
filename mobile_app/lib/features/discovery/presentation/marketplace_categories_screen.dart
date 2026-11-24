import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_components.dart';
import '../../../core/widgets/property_type_icon.dart';
import '../domain/smart_search_filters.dart';

const _purposeLabels = {'rent': 'الإيجارات', 'sale': 'البيع'};
const _categoryLabels = {
  'apartment': 'شقق',
  'house': 'منازل',
  'villa': 'فلل',
  'building': 'عمائر',
  'land': 'أراضٍ',
  'farm': 'مزارع',
  'shop': 'محلات',
  'office': 'مكاتب',
};

class MarketplaceCategoriesScreen extends StatelessWidget {
  const MarketplaceCategoriesScreen({super.key});

  @override
  Widget build(BuildContext context) => _CategoryMenu(
    title: 'الأقسام',
    choices: [
      for (final entry in _purposeLabels.entries)
        _CategoryTile(
          label: entry.value,
          icon: entry.key == 'rent' ? Icons.key_outlined : Icons.sell_outlined,
          onTap: () => context.push('/marketplace-categories/${entry.key}'),
        ),
    ],
  );
}

class MarketplaceCategoryTypesScreen extends StatelessWidget {
  const MarketplaceCategoryTypesScreen({required this.purpose, super.key});

  final String purpose;

  @override
  Widget build(BuildContext context) {
    final title = _purposeLabels[purpose];
    if (title == null) {
      return const Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppAppBar(title: 'الأقسام'),
          body: AppEmptyState(
            title: 'هذا القسم غير متاح',
            message: 'ارجع لاختيار الإيجارات أو البيع.',
          ),
        ),
      );
    }
    return _CategoryMenu(
      title: title,
      choices: [
        for (final entry in SmartSearchFilters.types.entries)
          _CategoryTile(
            label: _categoryLabels[entry.key] ?? entry.value,
            icon: propertyTypeIcon(entry.key),
            onTap: () => context.push(Uri(
              path: '/marketplace-section',
              queryParameters: {
                'section': purpose,
                'purpose': purpose,
                'type': entry.key,
              },
            ).toString()),
          ),
      ],
    );
  }
}

class _CategoryMenu extends StatelessWidget {
  const _CategoryMenu({required this.title, required this.choices});

  final String title;
  final List<Widget> choices;

  @override
  Widget build(BuildContext context) => Directionality(
    textDirection: TextDirection.rtl,
    child: Scaffold(
      appBar: AppAppBar(title: title),
      body: SafeArea(
        top: false,
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: choices.length,
          itemBuilder: (_, index) => choices[index],
          separatorBuilder: (_, __) => const SizedBox(height: 8),
        ),
      ),
    ),
  );
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AppSurface(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(label, style: theme.textTheme.titleMedium)),
          Icon(Icons.chevron_left, color: theme.colorScheme.onSurfaceVariant),
        ],
      ),
    );
  }
}
