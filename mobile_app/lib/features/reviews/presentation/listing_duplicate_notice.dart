import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_components.dart';
import '../domain/listing_duplicate_candidate.dart';

class ListingDuplicateNotice extends StatelessWidget {
  const ListingDuplicateNotice({super.key, required this.detection});

  final ListingDuplicateDetection detection;

  @override
  Widget build(BuildContext context) {
    final detectedByAi = detection.source == ListingDuplicateSource.ai;
    final reason = detection.reason;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppStatusBadge(
          label: detectedByAi ? 'تشابه رصده المساعد' : 'تشابه واضح رصده النظام',
          tone: detectedByAi ? AppStatusTone.info : AppStatusTone.warning,
        ),
        if (reason != null) ...[
          const SizedBox(height: AppSpacing.s4),
          Text(reason),
        ],
      ],
    );
  }
}
