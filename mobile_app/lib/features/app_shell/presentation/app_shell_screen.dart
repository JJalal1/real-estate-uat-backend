import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_components.dart';
import '../../account/data/auth_controller.dart';
import '../../account/presentation/account_screen.dart';
import '../../account/presentation/auth_gate.dart';
import '../../admin/presentation/general_manager_pages.dart';
import '../../bookings/presentation/bookings_screen.dart';
import '../../map/presentation/map_screen.dart';
import '../../messages/presentation/messages_screen.dart';
import '../../properties/presentation/my_listings_screen.dart';
import '../../support/presentation/support_tasks_screen.dart';
import '../../support/presentation/support_workspace_pages.dart';

class AppShellScreen extends ConsumerStatefulWidget {
  const AppShellScreen({super.key});

  @override
  ConsumerState<AppShellScreen> createState() => _AppShellScreenState();
}

class _AppShellScreenState extends ConsumerState<AppShellScreen> {
  int _index = 0;
  bool _exitDialogOpen = false;
  String? _lastMode;
  final Set<int> _visitedIndices = <int>{0};

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

  void _selectTab(int value) {
    if (value == _index) return;
    setState(() {
      _visitedIndices.add(value);
      _index = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).asData?.value;
    final mode = _modeFor(user);
    final shell = _shellFor(mode, user);

    if (_lastMode != mode) {
      _lastMode = mode;
      _index = 0;
      _visitedIndices
        ..clear()
        ..add(0);
    }
    if (_index >= shell.pages.length) {
      _index = 0;
      _visitedIndices
        ..clear()
        ..add(0);
    }

    final lazyPages = List<Widget>.generate(
      shell.pages.length,
      (pageIndex) => _visitedIndices.contains(pageIndex)
          ? shell.pages[pageIndex]
          : const SizedBox.shrink(),
      growable: false,
    );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _confirmExit();
        },
        child: Scaffold(
          body: IndexedStack(index: _index, children: lazyPages),
          bottomNavigationBar: AppNavigationBar(
            destinations: shell.items
                .map((item) => AppNavDestination(label: item.label, icon: item.icon))
                .toList(growable: false),
            selectedIndex: _index,
            onSelected: _selectTab,
          ),
        ),
      ),
    );
  }

  String _modeFor(dynamic user) {
    if (user == null) return 'anonymous';
    final roles = user.roles as List<String>;
    if (user.isPlatformOwner == true || roles.contains('super_admin')) {
      return 'platform';
    }
    if (roles.contains('support_manager')) return 'manager';
    if (roles.contains('support_agent')) return 'agent';
    if (user.hasVerifiedPublishingProfile == true) return 'advertiser';
    return 'regular';
  }

  _ShellData _shellFor(String mode, dynamic user) {
    switch (mode) {
      case 'agent':
        return const _ShellData(
          pages: [
            SupportAgentHomeScreen(),
            SupportTasksScreen(initialScope: 'inbox', title: 'الوارد'),
            SupportTasksScreen(initialScope: 'mine', title: 'مهامي'),
            Stage6AuthGate(child: MessagesScreen()),
            AccountScreen(),
          ],
          items: [
            _NavItemData(label: 'لوحة الدعم', icon: Icons.dashboard_outlined),
            _NavItemData(label: 'الوارد', icon: Icons.inbox_outlined),
            _NavItemData(label: 'مهامي', icon: Icons.assignment_ind_outlined),
            _NavItemData(label: 'الرسائل', icon: Icons.chat_bubble_outline),
            _NavItemData(label: 'حسابي', icon: Icons.account_circle_outlined),
          ],
        );
      case 'manager':
        return const _ShellData(
          pages: [
            SupportManagerHomeScreen(),
            SupportTasksScreen(initialScope: 'all', title: 'الأعمال'),
            SupportTeamScreen(),
            Stage6AuthGate(child: MessagesScreen()),
            AccountScreen(),
          ],
          items: [
            _NavItemData(label: 'لوحة الفريق', icon: Icons.space_dashboard_outlined),
            _NavItemData(label: 'الأعمال', icon: Icons.view_list_outlined),
            _NavItemData(label: 'الفريق', icon: Icons.groups_2_outlined),
            _NavItemData(label: 'الرسائل', icon: Icons.chat_bubble_outline),
            _NavItemData(label: 'حسابي', icon: Icons.account_circle_outlined),
          ],
        );
      case 'platform':
        return const _ShellData(
          pages: [
            GeneralManagerHomeScreen(),
            GeneralManagerMarketScreen(),
            GeneralManagerAdministrationScreen(),
            GeneralManagerReportsScreen(),
            AccountScreen(),
          ],
          items: [
            _NavItemData(label: 'الرئيسية', icon: Icons.space_dashboard_outlined),
            _NavItemData(label: 'السوق', icon: Icons.query_stats_outlined),
            _NavItemData(label: 'الإدارة', icon: Icons.account_tree_outlined),
            _NavItemData(label: 'التقارير', icon: Icons.analytics_outlined),
            _NavItemData(label: 'حسابي', icon: Icons.account_circle_outlined),
          ],
        );
      case 'advertiser':
        return const _ShellData(
          pages: [
            MapScreen(),
            Stage6AuthGate(child: MyListingsScreen()),
            Stage6AuthGate(child: MessagesScreen()),
            Stage6AuthGate(child: BookingsScreen()),
            AccountScreen(),
          ],
          items: [
            _NavItemData(label: 'العقارات', icon: Icons.travel_explore_outlined),
            _NavItemData(label: 'إعلاناتي', icon: Icons.inventory_2_outlined),
            _NavItemData(label: 'الرسائل', icon: Icons.chat_bubble_outline),
            _NavItemData(label: 'المعاينات', icon: Icons.calendar_month_outlined),
            _NavItemData(label: 'حسابي', icon: Icons.account_circle_outlined),
          ],
        );
      case 'regular':
        return const _ShellData(
          pages: [
            MapScreen(),
            Stage6AuthGate(child: MessagesScreen()),
            Stage6AuthGate(child: BookingsScreen()),
            AccountScreen(),
          ],
          items: [
            _NavItemData(label: 'العقارات', icon: Icons.travel_explore_outlined),
            _NavItemData(label: 'الرسائل', icon: Icons.chat_bubble_outline),
            _NavItemData(label: 'المعاينات', icon: Icons.calendar_month_outlined),
            _NavItemData(label: 'حسابي', icon: Icons.account_circle_outlined),
          ],
        );
      default:
        return const _ShellData(
          pages: [MapScreen(), AccountScreen()],
          items: [
            _NavItemData(label: 'العقارات', icon: Icons.travel_explore_outlined),
            _NavItemData(label: 'حسابي', icon: Icons.account_circle_outlined),
          ],
        );
    }
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
