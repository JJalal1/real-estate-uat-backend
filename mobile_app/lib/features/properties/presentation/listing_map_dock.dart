import 'package:flutter/material.dart';

import '../../../core/design/app_design.dart';

/// Presentation only: the picker owns coordinates, readiness and every action.
class ListingMapDock extends StatelessWidget {
  const ListingMapDock({
    required this.instruction,
    required this.primaryLabel,
    required this.onPrimary,
    this.message,
    this.loading = false,
    this.secondaryAction,
    super.key,
  });

  final String instruction;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final String? message;
  final bool loading;
  final Widget? secondaryAction;

  @override
  Widget build(BuildContext context) => AppActionDock(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(instruction, style: Theme.of(context).textTheme.titleSmall),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.s8),
              Text(message!, style: Theme.of(context).textTheme.bodyMedium),
            ],
            const SizedBox(height: AppSpacing.s12),
            AppButton(
              label: primaryLabel,
              icon: Icons.check_circle_outline,
              loading: loading,
              onPressed: onPrimary,
              expand: true,
            ),
            if (secondaryAction != null) ...[
              const SizedBox(height: AppSpacing.s8),
              secondaryAction!,
            ],
          ],
        ),
      );
}
