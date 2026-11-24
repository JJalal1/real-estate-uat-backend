import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/widgets/app_components.dart';

enum BrokerAchievementKind {
  firstDeal('أول صفقة مؤكدة', Icons.verified_outlined),
  replies('عملاء رددت عليهم', Icons.chat_bubble_outline),
  ratings('تقييمات العملاء', Icons.star_outline),
  inquiries('استفسارات على إعلاناتك', Icons.forum_outlined);

  const BrokerAchievementKind(this.label, this.icon);
  final String label;
  final IconData icon;
}

class BrokerAchievement {
  const BrokerAchievement(this.kind, this.count, {this.detail, this.onTap});

  final BrokerAchievementKind kind;
  final int count;
  final String? detail;
  final VoidCallback? onTap;
}

class BrokerAchievementCarousel extends StatefulWidget {
  const BrokerAchievementCarousel({required this.achievements, super.key});

  final List<BrokerAchievement> achievements;

  @override
  State<BrokerAchievementCarousel> createState() => _BrokerAchievementCarouselState();
}

class _BrokerAchievementCarouselState extends State<BrokerAchievementCarousel>
    with WidgetsBindingObserver {
  static const _interval = Duration(seconds: 6);
  final _pages = PageController(viewportFraction: .87, keepPage: false);
  final _pointers = <int>{};
  Timer? _advanceTimer;
  Timer? _highlightTimer;
  Set<BrokerAchievementKind> _newAchievements = {};
  ModalRoute<dynamic>? _route;
  int _currentPage = 0;
  bool _visible = true;
  bool _allowMotion = true;
  bool _stackCards = false;
  bool _foreground = true;
  bool _scrolling = false;
  bool _hovered = false;
  bool _focused = false;
  bool _auto = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    _visible = TickerMode.of(context);
    _allowMotion = !MediaQuery.disableAnimationsOf(context) &&
        !MediaQuery.accessibleNavigationOf(context);
    final stackCards = MediaQuery.textScalerOf(context).scale(16) >= 24;
    if (_stackCards != stackCards) {
      _stackCards = stackCards;
      _currentPage = 0;
      _scrolling = false;
      _hovered = false;
      _focused = false;
      _pointers.clear();
    }
    _scheduleAdvance();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _scheduleAdvance();
  }

  @override
  void didUpdateWidget(BrokerAchievementCarousel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = oldWidget.achievements;
    final current = widget.achievements;
    final oldCounts = {for (final item in previous) item.kind: item.count};
    final increased = {
      for (final item in current)
        if (item.count > (oldCounts[item.kind] ?? 0)) item.kind,
    };
    if (increased.isNotEmpty) {
      _highlightTimer?.cancel();
      _newAchievements = increased;
      _highlightTimer = Timer(const Duration(seconds: 24), () {
        if (mounted) setState(_newAchievements.clear);
      });
    }
    final previousIndex = previous.isEmpty ? -1 : _currentPage % previous.length;
    final oldKind = previousIndex < 0 ? null : previous[previousIndex].kind;
    final newIndex = current.indexWhere((item) => item.kind == oldKind);
    if (previous.length != current.length || previousIndex != newIndex) {
      final page = newIndex < 0 ? 0 : newIndex;
      _currentPage = page;
      if (current.length < 2) {
        _scrolling = false;
        _pointers.clear();
        _hovered = false;
        _focused = false;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pages.hasClients && widget.achievements.length > page) {
          _pages.jumpToPage(page);
        }
      });
    }
    _scheduleAdvance();
  }

  void _scheduleAdvance() {
    _advanceTimer?.cancel();
    if (!_auto || !_allowMotion || _stackCards || !_visible || !_foreground || _scrolling ||
        _focused || _hovered || _pointers.isNotEmpty || widget.achievements.length < 2) {
      return;
    }
    _advanceTimer = Timer(_interval, () {
      if (!mounted) return;
      if (!_pages.hasClients || _route?.isCurrent == false) {
        _scheduleAdvance();
        return;
      }
      unawaited(_pages.animateToPage(
        _currentPage + 1,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeInOut,
      ));
    });
  }

  bool _handleScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification) {
      _scrolling = true;
      _advanceTimer?.cancel();
    }
    if (notification is ScrollEndNotification) {
      _scrolling = false;
      final count = widget.achievements.length;
      final page = _currentPage;
      if (count > 1 && page >= count) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _pages.hasClients && _currentPage == page &&
              widget.achievements.length == count) {
            _pages.jumpToPage(page % count);
          }
        });
      }
      _scheduleAdvance();
    }
    return false;
  }

  void _releasePointer(PointerEvent event) {
    _pointers.remove(event.pointer);
    _scheduleAdvance();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _advanceTimer?.cancel();
    _highlightTimer?.cancel();
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final achievements = widget.achievements;
    if (achievements.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scale = MediaQuery.textScalerOf(context);
    final extraHeight = (scale.scale(16) - 16).clamp(0.0, double.infinity).toDouble();
    final hasRatingGoal = achievements.any((item) => item.kind == BrokerAchievementKind.ratings);
    final height = (hasRatingGoal ? 100.0 : 76.0) + 6 * extraHeight;

    Widget card(BrokerAchievement achievement) => _AchievementCard(
      achievement: achievement,
      isNew: _newAchievements.contains(achievement.kind),
      animate: _allowMotion,
    );

    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Expanded(child: Text('إنجازاتك', style: theme.textTheme.titleMedium)),
            if (achievements.length > 1 && _allowMotion && !_stackCards)
              IconButton(
                key: const ValueKey('broker-achievement-autoplay'),
                tooltip: _auto ? 'إيقاف التنقل التلقائي' : 'استئناف التنقل التلقائي',
                icon: Icon(_auto ? Icons.pause_circle_outline : Icons.play_circle_outline, size: 20),
                onPressed: () {
                  setState(() => _auto = !_auto);
                  _scheduleAdvance();
                },
              ),
          ]),
          if (achievements.length == 1 || !_allowMotion || _stackCards)
            const SizedBox(height: 8),
          if (_stackCards)
            Column(
              key: const ValueKey('broker-achievement-carousel'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (index, achievement) in achievements.indexed) ...[
                  if (index > 0) const SizedBox(height: 8),
                  card(achievement),
                ],
              ],
            )
          else SizedBox(
            key: const ValueKey('broker-achievement-carousel'),
            height: height,
            child: achievements.length == 1
                ? card(achievements.single)
                : Focus(
                    canRequestFocus: false,
                    onFocusChange: (focused) {
                      _focused = focused;
                      _scheduleAdvance();
                    },
                    child: MouseRegion(
                      onEnter: (_) { _hovered = true; _scheduleAdvance(); },
                      onExit: (_) { _hovered = false; _scheduleAdvance(); },
                      child: Listener(
                        onPointerDown: (event) {
                          _pointers.add(event.pointer);
                          _scheduleAdvance();
                        },
                        onPointerUp: _releasePointer,
                        onPointerCancel: _releasePointer,
                        child: NotificationListener<ScrollNotification>(
                          onNotification: _handleScroll,
                          child: PageView.builder(
                            controller: _pages,
                            padEnds: false,
                            allowImplicitScrolling: true,
                            // Two preview copies let the rail wrap without a backward scroll.
                            itemCount: achievements.length + 2,
                            onPageChanged: (page) => _currentPage = page,
                            itemBuilder: (context, page) => ExcludeSemantics(
                              excluding: page >= achievements.length,
                              child: Padding(
                                padding: const EdgeInsetsDirectional.only(end: 8),
                                child: card(achievements[page % achievements.length]),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _AchievementCard extends StatelessWidget {
  const _AchievementCard({required this.achievement, required this.isNew, required this.animate});

  final BrokerAchievement achievement;
  final bool isNew;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final kind = achievement.kind;
    final isRating = kind == BrokerAchievementKind.ratings;
    final showCount = !isRating && kind != BrokerAchievementKind.firstDeal;
    final inlineCount = showCount && MediaQuery.textScalerOf(context).scale(14) > 21;
    final (tint, ink) = switch (kind) {
      BrokerAchievementKind.firstDeal || BrokerAchievementKind.ratings =>
        (scheme.tertiaryContainer, scheme.onTertiaryContainer),
      BrokerAchievementKind.replies => (scheme.primaryContainer, scheme.onPrimaryContainer),
      BrokerAchievementKind.inquiries => (scheme.secondaryContainer, scheme.onSecondaryContainer),
    };
    return AppSurface(
      padding: EdgeInsets.zero,
      onTap: achievement.onTap,
      child: AnimatedContainer(
        duration: animate ? const Duration(milliseconds: 240) : Duration.zero,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isNew ? tint.withValues(alpha: .35) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(12)),
            child: Icon(kind.icon, color: ink, size: 21),
          ),
          const SizedBox(width: 9),
          Expanded(child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                inlineCount ? '${achievement.count} ${kind.label}' : kind.label,
                style: theme.textTheme.titleSmall,
              ),
              if (achievement.detail case final detail?)
                Text(detail, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
              if (isRating)
                _RatingGoal(count: achievement.count, hasAction: achievement.onTap != null),
            ],
          )),
          if (showCount && !inlineCount)
            Padding(
              padding: const EdgeInsetsDirectional.only(start: 7),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 62),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text('${achievement.count}', style: theme.textTheme.titleLarge?.copyWith(color: ink)),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

class _RatingGoal extends StatelessWidget {
  const _RatingGoal({required this.count, required this.hasAction});

  static const _target = 5;
  final int count;
  final bool hasAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final progressText = count >= _target
        ? 'الهدف مكتمل · $count تقييم'
        : '$count من $_target تقييمات';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ExcludeSemantics(child: Text(progressText, style: theme.textTheme.bodySmall)),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            key: const ValueKey('broker-achievement-rating-progress'),
            value: count.clamp(0, _target) / _target,
            minHeight: 4,
            color: scheme.tertiary,
            backgroundColor: scheme.tertiaryContainer,
            semanticsLabel: 'هدف تقييمات العملاء',
            semanticsValue: progressText,
          ),
        ),
        if (hasAction) ...[
          const SizedBox(height: 4),
          Text('عرض ملخص التقييم', style: theme.textTheme.labelMedium?.copyWith(color: scheme.primary)),
        ],
      ],
    );
  }
}
