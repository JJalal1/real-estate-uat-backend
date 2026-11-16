import 'package:flutter/material.dart';

class DiscoverySectionHeading extends StatelessWidget {
  const DiscoverySectionHeading({required this.hasExact, super.key});
  final bool hasExact;
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsetsDirectional.only(top: 12, bottom: 8),
    child: Text(hasExact ? 'نتائج قريبة من بحثك' : 'ما فيه مطابق تمامًا، هذه أقرب النتائج',
      key: const ValueKey('nearby-search-section'), style: Theme.of(context).textTheme.titleSmall));
}
