import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../account/presentation/account_screen.dart';
import '../../account/presentation/auth_gate.dart';
import '../../bookings/presentation/bookings_screen.dart';
import '../../map/presentation/map_screen.dart';
import '../../messages/presentation/messages_screen.dart';
import '../../services/presentation/services_screen.dart';

class AppShellScreen extends StatefulWidget {
  const AppShellScreen({super.key});

  @override
  State<AppShellScreen> createState() => _AppShellScreenState();
}

class _AppShellScreenState extends State<AppShellScreen> {
  int _index = 1;
  bool _exitDialogOpen = false;

  static const _pages = <Widget>[
    AccountScreen(),
    MapScreen(),
    BookingsScreen(),
    Stage6AuthGate(child: MessagesScreen()),
    ServicesScreen(),
  ];

  Future<void> _confirmExit() async {
    if (_exitDialogOpen || !mounted) {
      return;
    }
    _exitDialogOpen = true;
    final shouldExit = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('الخروج من التطبيق؟'),
          content: const Text(
            'هل تريد إغلاق التطبيق الآن؟ يمكنك اختيار إلغاء للمتابعة.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const Icon(Icons.exit_to_app),
              label: const Text('خروج'),
            ),
          ],
        ),
      ),
    );
    _exitDialogOpen = false;
    if (shouldExit == true && mounted) {
      await SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) {
            _confirmExit();
          }
        },
        child: Scaffold(
          body: IndexedStack(index: _index, children: _pages),
          bottomNavigationBar: _AppBottomNavigationBar(
            selectedIndex: _index,
            onSelected: (value) => setState(() => _index = value),
          ),
        ),
      ),
    );
  }
}

class _AppBottomNavigationBar extends StatelessWidget {
  const _AppBottomNavigationBar({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  static const _items = <_NavItemData>[
    _NavItemData(label: 'حسابي', icon: Icons.account_circle_outlined),
    _NavItemData(label: 'الإعلانات', icon: Icons.location_on_outlined),
    _NavItemData(label: 'الحجوزات', icon: Icons.calendar_month_outlined),
    _NavItemData(label: 'المحادثات', icon: Icons.chat_bubble_outline),
    _NavItemData(label: 'الخدمات', icon: Icons.apps_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      elevation: 12,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 72,
          child: Row(
            children: List.generate(_items.length, (index) {
              final item = _items[index];
              final selected = index == selectedIndex;
              return Expanded(
                child: Semantics(
                  button: true,
                  selected: selected,
                  label: item.label,
                  child: InkWell(
                    onTap: () => onSelected(index),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: selected ? 38 : 32,
                            height: 30,
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppTheme.brandSoft
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              item.icon,
                              size: selected ? 24 : 22,
                              color: selected
                                  ? AppTheme.brandStrong
                                  : AppTheme.textMuted,
                            ),
                          ),
                          const SizedBox(height: 3),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              item.label,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 10.5,
                                height: 1,
                                fontWeight: selected
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: selected
                                    ? AppTheme.brandStrong
                                    : AppTheme.textMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _NavItemData {
  const _NavItemData({required this.label, required this.icon});

  final String label;
  final IconData icon;
}
