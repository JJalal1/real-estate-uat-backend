import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/app_components.dart';

/// Keeps two related inputs readable without changing their controllers,
/// validators, focus behavior or field order.
class AppFieldPair extends StatelessWidget {
  const AppFieldPair({required this.first, required this.second, super.key});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth < AppLayout.narrowBreakpoint ||
              MediaQuery.textScalerOf(context).scale(16) > 20) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [first, const SizedBox(height: AppLayout.fieldGap), second],
            );
          }
          return Row(children: [
            Expanded(child: first),
            const SizedBox(width: AppLayout.fieldGap),
            Expanded(child: second),
          ]);
        },
      );
}

/// Constrains content, not its height. The caller retains scroll ownership.
class AppContentFrame extends StatelessWidget {
  const AppContentFrame({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final gutter = constraints.maxWidth >= AppLayout.wideBreakpoint
              ? AppLayout.widePageGutter
              : AppLayout.compactPageGutter;
          return Align(
            alignment: AlignmentDirectional.topCenter,
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppLayout.contentMaxWidth,
              ),
              child: Padding(
                padding: EdgeInsetsDirectional.symmetric(horizontal: gutter),
                child: SizedBox(width: double.infinity, child: child),
              ),
            ),
          );
        },
      );
}

/// A page introduction that grows with Arabic copy and accessibility scaling.
class AppPageHeading extends StatelessWidget {
  const AppPageHeading({
    required this.title,
    this.eyebrow,
    this.subtitle,
    this.actions = const [],
    super.key,
  });

  final String title;
  final String? eyebrow;
  final String? subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(vertical: AppSpacing.s24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (eyebrow != null) ...[
            Text(
              eyebrow!,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
          ],
          Semantics(
            header: true,
            child: Text(title, style: theme.textTheme.headlineLarge),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpacing.s8),
            Text(
              subtitle!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (actions.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s16),
            AppActionGroup(children: actions),
          ],
        ],
      ),
    );
  }
}

/// Wraps actions without changing their order, callbacks or enabled state.
class AppActionGroup extends StatelessWidget {
  const AppActionGroup({required this.children, super.key});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: AppSpacing.s8,
        runSpacing: AppSpacing.s8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: children,
      );
}

class AppSectionCard extends StatelessWidget {
  const AppSectionCard({
    required this.title,
    required this.child,
    this.subtitle,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => AppSurface(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppSectionHeader(
              title: title,
              subtitle: subtitle,
              actionLabel: actionLabel,
              onAction: onAction,
            ),
            const SizedBox(height: AppSpacing.s20),
            child,
          ],
        ),
      );
}

/// Opens an existing search journey; owns no query or filtering behavior.
class AppSearchEntry extends StatelessWidget {
  const AppSearchEntry({
    required this.label,
    required this.onTap,
    this.onFilter,
    this.filterLabel = 'تصفية النتائج',
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final VoidCallback? onFilter;
  final String filterLabel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppSurface(
      padding: const EdgeInsetsDirectional.all(AppSpacing.s4),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(AppRadii.control),
              child: Semantics(
                button: true,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: AppSizes.fieldMinHeight,
                  ),
                  child: Padding(
                    padding: const EdgeInsetsDirectional.all(AppSpacing.s12),
                    child: Row(
                      children: [
                        Icon(Icons.search, color: scheme.primary),
                        const SizedBox(width: AppSpacing.s12),
                        Expanded(
                          child: Text(
                            label,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (onFilter != null) ...[
            const SizedBox(width: AppSpacing.s4),
            AppIconButton(
              icon: Icons.tune,
              tooltip: filterLabel,
              onPressed: onFilter,
            ),
          ],
        ],
      ),
    );
  }
}

/// A decorative identity mark. Verification/role badges must be supplied by
/// the caller from existing server-backed state; never inferred here.
class AppIdentityMark extends StatelessWidget {
  const AppIdentityMark({this.icon = Icons.person_outline, super.key});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Container(
        width: AppSizes.identityMark,
        height: AppSizes.identityMark,
        decoration: BoxDecoration(
          color: scheme.primaryContainer,
          borderRadius: BorderRadius.circular(AppRadii.card),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Icon(icon, color: scheme.onPrimaryContainer),
      ),
    );
  }
}
