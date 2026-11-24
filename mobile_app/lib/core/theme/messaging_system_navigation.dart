import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class MessagingSystemNavigation extends StatelessWidget {
  const MessagingSystemNavigation({required this.child, this.enabled = true, super.key});

  final Widget child;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final background = dark ? theme.colorScheme.surface : Colors.white;
    final inset = MediaQuery.viewPaddingOf(context).bottom;

    return Stack(
      fit: StackFit.expand,
      children: [
        child,
        if (enabled && theme.platform == TargetPlatform.android)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: inset > 0 ? inset : 1,
            child: IgnorePointer(
              child: AnnotatedRegion<SystemUiOverlayStyle>(
                value: SystemUiOverlayStyle(
                  systemNavigationBarColor: background,
                  systemNavigationBarDividerColor: background,
                  systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
                  systemNavigationBarContrastEnforced: false,
                ),
                // Edge-to-edge Android draws behind the transparent system bar.
                child: ColoredBox(color: inset > 0 ? background : Colors.transparent),
              ),
            ),
          ),
      ],
    );
  }
}
