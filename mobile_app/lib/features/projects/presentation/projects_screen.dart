import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class ProjectsScreen extends StatelessWidget {
  const ProjectsScreen({super.key});

  static const _projects = <_ProjectData>[
    _ProjectData(
      title: 'واحة النخيل',
      subtitle: 'مجمع سكني حديث قريب من الخدمات',
      price: 'يبدأ من 48,000,000 ريال',
      location: 'حدة، صنعاء',
      image: 'http://127.0.0.1:8000/demo-properties/property-exterior.png',
      tags: ['فلل', 'وحدات جاهزة'],
    ),
    _ProjectData(
      title: 'بوابة المدينة',
      subtitle: 'شقق بتصاميم عملية ومساحات متنوعة',
      price: 'يبدأ من 23,500,000 ريال',
      location: 'شارع الستين، صنعاء',
      image: 'http://127.0.0.1:8000/demo-properties/property-interior.png',
      tags: ['شقق', 'تحت الإنشاء'],
    ),
    _ProjectData(
      title: 'روابي صنعاء',
      subtitle: 'مشروع هادئ مع خيارات دفع مرنة',
      price: 'يبدأ من 31,000,000 ريال',
      location: 'الروضة، صنعاء',
      image: 'http://127.0.0.1:8000/demo-properties/property-location.png',
      tags: ['دور', 'حجز مبكر'],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('المشاريع العقارية'),
          actions: [
            IconButton(
              tooltip: 'بحث',
              onPressed: () => _showInfo(context, 'بحث المشاريع'),
              icon: const Icon(Icons.search),
            ),
          ],
        ),
        body: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
                child: _ProjectFilterBar(onMore: () => _showFilters(context)),
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_projects.length} مشاريع مميزة',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                ),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _showInfo(
                        context,
                        'سيتم ربط عرض الخريطة بمشاريع المطورين عند إضافة بيانات المشاريع إلى الخادم.',
                      ),
                      icon: const Icon(Icons.map_outlined),
                      label: const Text('الخريطة'),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _ProjectCard(
                      project: _projects[index],
                      onTap: () => _showProject(context, _projects[index]),
                    ),
                  ),
                  childCount: _projects.length,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showFilters(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => const _ProjectsMoreFilters(),
    );
  }

  void _showProject(BuildContext context, _ProjectData project) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Center(child: _SheetHandle()),
            const SizedBox(height: 16),
            Text(
              project.title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 8),
            Text(project.subtitle),
            const SizedBox(height: 12),
            Text(
              project.price,
              style: const TextStyle(
                color: AppTheme.brandStrong,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text('طلب معلومات عن المشروع'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showInfo(BuildContext context, String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }
}

class _ProjectFilterBar extends StatefulWidget {
  const _ProjectFilterBar({required this.onMore});

  final VoidCallback onMore;

  @override
  State<_ProjectFilterBar> createState() => _ProjectFilterBarState();
}

class _ProjectFilterBarState extends State<_ProjectFilterBar> {
  int _purpose = 0;
  int _type = 0;

  @override
  Widget build(BuildContext context) {
    const purposes = ['الكل', 'للبيع', 'للإيجار'];
    const types = ['الكل', 'شقة', 'فيلا', 'دور', 'أرض'];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: AppTheme.outlineSoft),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: SegmentedButton<int>(
                  showSelectedIcon: false,
                  segments: List.generate(
                    purposes.length,
                    (index) => ButtonSegment(
                      value: index,
                      label: Text(purposes[index]),
                    ),
                  ),
                  selected: {_purpose},
                  onSelectionChanged: (value) {
                    setState(() => _purpose = value.first);
                  },
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: widget.onMore,
                icon: const Icon(Icons.tune, size: 18),
                label: const Text('المزيد'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: types.length,
              separatorBuilder: (_, __) => const SizedBox(width: 7),
              itemBuilder: (context, index) => ChoiceChip(
                label: Text(types[index]),
                selected: _type == index,
                onSelected: (_) => setState(() => _type = index),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project, required this.onTap});

  final _ProjectData project;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Image.network(
                    project.image,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => const _ProjectImageFallback(),
                  ),
                  PositionedDirectional(
                    top: 12,
                    start: 12,
                    child: Wrap(
                      spacing: 7,
                      children: project.tags
                          .map(
                            (tag) => Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.94),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                tag,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    project.title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    project.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppTheme.textMuted),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    project.price,
                    style: const TextStyle(
                      color: AppTheme.brandStrong,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 18,
                        color: AppTheme.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          project.location,
                          style: const TextStyle(color: AppTheme.textMuted),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectsMoreFilters extends StatefulWidget {
  const _ProjectsMoreFilters();

  @override
  State<_ProjectsMoreFilters> createState() => _ProjectsMoreFiltersState();
}

class _ProjectsMoreFiltersState extends State<_ProjectsMoreFilters> {
  double _progress = 0.45;
  bool _ready = false;
  bool _installments = true;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Center(child: _SheetHandle()),
          const SizedBox(height: 16),
          Text(
            'مزيد من فلاتر المشاريع',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
          ),
          const SizedBox(height: 14),
          SwitchListTile(
            value: _ready,
            onChanged: (value) => setState(() => _ready = value),
            title: const Text('وحدات جاهزة'),
          ),
          SwitchListTile(
            value: _installments,
            onChanged: (value) => setState(() => _installments = value),
            title: const Text('خيارات تقسيط'),
          ),
          const SizedBox(height: 6),
          Text('نسبة اكتمال المشروع: ${(_progress * 100).round()}% أو أكثر'),
          Slider(
            value: _progress,
            onChanged: (value) => setState(() => _progress = value),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('تطبيق الفلاتر'),
          ),
        ],
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 5,
      decoration: BoxDecoration(
        color: AppTheme.outlineSoft,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _ProjectImageFallback extends StatelessWidget {
  const _ProjectImageFallback();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: AppTheme.brandSoft,
      child: Center(
        child: Icon(
          Icons.apartment_outlined,
          size: 58,
          color: AppTheme.brandStrong,
        ),
      ),
    );
  }
}

class _ProjectData {
  const _ProjectData({
    required this.title,
    required this.subtitle,
    required this.price,
    required this.location,
    required this.image,
    required this.tags,
  });

  final String title;
  final String subtitle;
  final String price;
  final String location;
  final String image;
  final List<String> tags;
}
