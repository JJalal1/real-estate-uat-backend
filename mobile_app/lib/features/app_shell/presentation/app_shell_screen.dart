import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../account/data/auth_controller.dart';
import '../../account/presentation/access_control_screen.dart';
import '../../account/presentation/account_screen.dart';
import '../../account/presentation/auth_gate.dart';
import '../../bookings/presentation/bookings_screen.dart';
import '../../map/presentation/map_screen.dart';
import '../../messages/presentation/messages_screen.dart';
import '../../services/presentation/services_screen.dart';
import '../../support/presentation/support_tasks_screen.dart';
import '../../support/presentation/support_workspace_pages.dart';

class AppShellScreen extends ConsumerStatefulWidget {
  const AppShellScreen({super.key});

  @override
  ConsumerState<AppShellScreen> createState() => _AppShellScreenState();
}

class _AppShellScreenState extends ConsumerState<AppShellScreen> {
  int _index = 1;
  bool _exitDialogOpen = false;
  String? _lastMode;

  Future<void> _confirmExit() async {
    if (_exitDialogOpen || !mounted) return;
    _exitDialogOpen = true;
    final shouldExit = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('الخروج من التطبيق؟'),
          content: const Text('هل تريد إغلاق التطبيق الآن؟ يمكنك اختيار إلغاء للمتابعة.'),
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
    if (shouldExit == true && mounted) await SystemNavigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).asData?.value;
    final mode = _modeFor(user);
    final shell = _shellFor(mode);

    if (_lastMode != mode) {
      _lastMode = mode;
      _index = mode == 'regular' ? 1 : 0;
    }
    if (_index >= shell.pages.length) _index = 0;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _confirmExit();
        },
        child: Scaffold(
          body: IndexedStack(index: _index, children: shell.pages),
          bottomNavigationBar: _RoleBottomNavigationBar(
            items: shell.items,
            selectedIndex: _index,
            onSelected: (value) => setState(() => _index = value),
          ),
        ),
      ),
    );
  }

  String _modeFor(dynamic user) {
    if (user == null) return 'regular';
    final roles = user.roles as List<String>;
    if (user.isPlatformOwner == true || roles.contains('super_admin')) {
      return 'platform';
    }
    if (roles.contains('support_manager')) return 'manager';
    if (roles.contains('support_agent')) return 'agent';
    return 'regular';
  }

  _ShellData _shellFor(String mode) {
    switch (mode) {
      case 'agent':
        return const _ShellData(
          pages: [
            SupportAgentHomeScreen(),
            SupportTasksScreen(initialScope: 'mine', title: 'مهامي'),
            SupportTasksScreen(initialScope: 'inbox', title: 'مركز الدعم'),
            Stage6AuthGate(child: MessagesScreen()),
            AccountScreen(),
          ],
          items: [
            _NavItemData(label: 'الرئيسية', icon: Icons.dashboard_outlined),
            _NavItemData(label: 'مهامي', icon: Icons.assignment_ind_outlined),
            _NavItemData(label: 'مركز الدعم', icon: Icons.support_agent_outlined),
            _NavItemData(label: 'الرسائل', icon: Icons.chat_bubble_outline),
            _NavItemData(label: 'حسابي', icon: Icons.account_circle_outlined),
          ],
        );
      case 'manager':
        return const _ShellData(
          pages: [
            SupportManagerHomeScreen(),
            SupportTasksScreen(initialScope: 'all', title: 'كل الأعمال'),
            SupportTeamScreen(),
            SupportTasksScreen(initialScope: 'all', initialType: 'report', title: 'البلاغات'),
            AccountScreen(),
          ],
          items: [
            _NavItemData(label: 'لوحة الدعم', icon: Icons.space_dashboard_outlined),
            _NavItemData(label: 'الأعمال', icon: Icons.view_list_outlined),
            _NavItemData(label: 'الفريق', icon: Icons.groups_2_outlined),
            _NavItemData(label: 'البلاغات', icon: Icons.report_outlined),
            _NavItemData(label: 'حسابي', icon: Icons.account_circle_outlined),
          ],
        );
      case 'platform':
        return const _ShellData(
          pages: [
            PlatformAdminHomeScreen(),
            PlatformReviewsScreen(),
            AccessControlScreen(),
            PlatformOperationsScreen(),
            AccountScreen(),
          ],
          items: [
            _NavItemData(label: 'لوحة الإدارة', icon: Icons.dashboard_customize_outlined),
            _NavItemData(label: 'المراجعات', icon: Icons.fact_check_outlined),
            _NavItemData(label: 'المستخدمون', icon: Icons.manage_accounts_outlined),
            _NavItemData(label: 'المنصة', icon: Icons.hub_outlined),
            _NavItemData(label: 'حسابي', icon: Icons.account_circle_outlined),
          ],
        );
      default:
        return const _ShellData(
          pages: [
            AccountScreen(),
            MapScreen(),
            BookingsScreen(),
            Stage6AuthGate(child: MessagesScreen()),
            ServicesScreen(),
          ],
          items: [
            _NavItemData(label: 'حسابي', icon: Icons.account_circle_outlined),
            _NavItemData(label: 'الإعلانات', icon: Icons.location_on_outlined),
            _NavItemData(label: 'الحجوزات', icon: Icons.calendar_month_outlined),
            _NavItemData(label: 'المحادثات', icon: Icons.chat_bubble_outline),
            _NavItemData(label: 'الخدمات', icon: Icons.apps_outlined),
          ],
        );
    }
  }
}

class _RoleBottomNavigationBar extends StatelessWidget {
  const _RoleBottomNavigationBar({
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<_NavItemData> items;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

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
            children: List.generate(items.length, (index) {
              final item = items[index];
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
                              color: selected ? AppTheme.brandSoft : Colors.transparent,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              item.icon,
                              size: selected ? 24 : 22,
                              color: selected ? AppTheme.brandStrong : AppTheme.textMuted,
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
                                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                                color: selected ? AppTheme.brandStrong : AppTheme.textMuted,
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

class _ShellData {
  const _ShellData({required this.pages, required this.items});
  final List<Widget> pages;
  final List<_NavItemData> items;
}

class _NavItemData {
  const _NavItemData({required this.label, required this.icon});
  final String label;
  final IconData icon;
}
