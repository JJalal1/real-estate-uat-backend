import 'package:flutter/material.dart';

/// A user scroll can request the next page, while layout, camera setup and
/// programmatic scroll restoration leave the current page unchanged.
class SearchResultPagination extends StatelessWidget {
  const SearchResultPagination({required this.child, this.onLoadMore, super.key});

  final Widget child;
  final VoidCallback? onLoadMore;

  @override
  Widget build(BuildContext context) {
    final load = onLoadMore;
    return NotificationListener<ScrollUpdateNotification>(
      onNotification: (notification) {
        if (load != null && notification.depth == 0 && notification.dragDetails != null &&
            (notification.scrollDelta ?? 0) > 0 && notification.metrics.extentAfter <= 160) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted && ModalRoute.of(context)?.isCurrent != false) load();
          });
        }
        return false;
      },
      child: child,
    );
  }
}
