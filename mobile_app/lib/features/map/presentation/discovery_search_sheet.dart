import 'package:flutter/material.dart';

import '../../../core/design/app_design.dart';

class DiscoverySearchSheet extends StatefulWidget {
  const DiscoverySearchSheet({
    required this.initialValue,
    required this.suggestions,
    required this.recentSearches,
    super.key,
  });

  final String initialValue;
  final List<String> suggestions;
  final List<String> recentSearches;

  @override
  State<DiscoverySearchSheet> createState() => _DiscoverySearchSheetState();
}

class _DiscoverySearchSheetState extends State<DiscoverySearchSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _controller.text.trim().toLowerCase();
    final suggestions = widget.suggestions
        .where((value) => query.isEmpty || value.toLowerCase().contains(query))
        .take(6)
        .toList(growable: false);

    return SingleChildScrollView(
      padding: EdgeInsetsDirectional.fromSTEB(
        AppLayout.compactPageGutter,
        AppSpacing.s8,
        AppLayout.compactPageGutter,
        MediaQuery.viewInsetsOf(context).bottom + AppSpacing.s24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AppSectionHeader(title: 'ابحث عن عقارك'),
          const SizedBox(height: AppSpacing.s16),
          TextField(
            controller: _controller,
            autofocus: true,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
              hintText: 'اسم منطقة، شارع أو عقار',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
          if (query.isEmpty && widget.recentSearches.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s24),
            const AppSectionHeader(title: 'بحثت مؤخراً'),
            const SizedBox(height: AppSpacing.s12),
            Wrap(
              spacing: AppSpacing.s8,
              runSpacing: AppSpacing.s8,
              children: widget.recentSearches.map((value) => ActionChip(
                avatar: const Icon(Icons.history_rounded),
                label: Text(value),
                onPressed: () => Navigator.of(context).pop(value),
              )).toList(growable: false),
            ),
          ],
          if (suggestions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s24),
            AppSurface(
              padding: EdgeInsetsDirectional.zero,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var index = 0; index < suggestions.length; index++) ...[
                    if (index > 0) const Divider(),
                    AppListRow(
                      leading: const Icon(Icons.location_on_outlined),
                      title: suggestions[index],
                      onTap: () => Navigator.of(context).pop(suggestions[index]),
                    ),
                  ],
                ],
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.s24),
          AppButton(
            label: 'عرض النتائج',
            icon: Icons.search,
            onPressed: () => Navigator.of(context).pop(_controller.text),
            expand: true,
          ),
          const SizedBox(height: AppSpacing.s8),
          AppButton(
            label: 'مسح البحث',
            style: AppButtonStyle.outlined,
            onPressed: () => Navigator.of(context).pop(''),
            expand: true,
          ),
        ],
      ),
    );
  }
}
