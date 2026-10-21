import 'package:flutter/material.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/widgets/app_components.dart';
import '../../account/data/auth_controller.dart';
import '../../account/presentation/account_screen.dart';
import '../../account/presentation/auth_gate.dart';
import '../../admin/presentation/general_manager_finance_hubs.dart';
import '../../admin/presentation/general_manager_pages.dart';
import '../../discovery/presentation/marketplace_home_screen.dart';
import '../../messages/presentation/messages_screen.dart';
import '../../properties/presentation/my_listings_screen.dart';
import '../../map/presentation/map_screen.dart';
import '../../discovery/presentation/smart_search_assistant.dart';
import 'listing_creation_menu.dart';
import '../../support/presentation/support_tasks_screen.dart';
import '../../support/presentation/support_workspace_pages.dart';

class AppShellScreen extends ConsumerStatefulWidget {
  const AppShellScreen({super.key});

  @override
  ConsumerState<AppShellScreen> createState() => _AppShellScreenState();
}

class _AppShellScreenState extends ConsumerState<AppShellScreen> {
  int _index = 0;
  bool _exitDialogOpen = false, _createMenuOpen = false, _openingEditor = false;
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
            EbrokerFilledButton.icon(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              icon: const EbrokerIcon(Icons.exit_to_app),
              label: const Text('خروج'),
            ),
          ],
        ),
      ),
    );
    _exitDialogOpen = false;
    if (shouldExit == true && mounted) await SystemNavigator.pop();
  }

  void _createListing() {
    if (_openingEditor) return;
    FocusManager.instance.primaryFocus?.unfocus();
    ref.read(brokerAssistantMenuProvider.notifier).state = false;
    if (ref.read(authControllerProvider).asData?.value?.hasVerifiedProfessionalProfile == true) {
      _openingEditor = true;
      context.push('/add-property?assistant=0').whenComplete(() => _openingEditor = false);
      return;
    }
    setState(() => _createMenuOpen = !_createMenuOpen);
  }

  void _closeCreationMenu() {
    if (_createMenuOpen) setState(() => _createMenuOpen = false);
  }

  Future<void> _selectCreationMode(bool assisted) async {
    if (!_createMenuOpen || _openingEditor) return;
    setState(() => _createMenuOpen = false);
    _openingEditor = true;
    try {
      await context.push('/add-property?assistant=${assisted ? 1 : 0}');
    } finally {
      _openingEditor = false;
    }
  }

  void _selectTab(int value) {
    _closeCreationMenu();
    ref.read(brokerAssistantMenuProvider.notifier).state = false;
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

    final accountScope = '$mode:${user?.id ?? 'guest'}';
    if (_lastMode != accountScope) {
      _lastMode = accountScope;
      _index = 0;
      _createMenuOpen = false;
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
          ? KeyedSubtree(key: ValueKey('$accountScope:$pageIndex'), child: shell.pages[pageIndex])
          : const SizedBox.shrink(),
      growable: false,
    );

    return Directionality(
      textDirection: TextDirection.rtl,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) {
            if (ref.read(brokerAssistantMenuProvider)) {
              ref.read(brokerAssistantMenuProvider.notifier).state = false;
            } else if (_createMenuOpen) {
              _closeCreationMenu();
            } else {
              _confirmExit();
            }
          }
        },
        child: Scaffold(
          body: Stack(children: [
            ExcludeSemantics(excluding: _createMenuOpen,
              child: IndexedStack(index: _index, children: lazyPages)),
            if (const ['anonymous', 'regular', 'advertiser'].contains(mode))
              ListingCreationMenu(isOpen: _createMenuOpen,
                onClose: _closeCreationMenu, onSelected: _selectCreationMode),
          ]),
          bottomNavigationBar: AppNavigationBar(
            destinations: shell.items
                .map((item) => AppNavDestination(label: item.label, icon: item.icon))
                .toList(growable: false),
            selectedIndex: _index,
            onSelected: _selectTab,
            onCreate: const ['anonymous', 'regular', 'advertiser'].contains(mode) ? _createListing : null,
            createExpanded: _createMenuOpen,
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
    if (user.hasVerifiedProfessionalProfile == true) return 'advertiser';
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
            GeneralManagerHomeFinancialOverlay(),
            GeneralManagerMarketScreen(),
            GeneralManagerAdministrationFinancialHubScreen(),
            GeneralManagerReportsFinancialHubScreen(),
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
        return const _ShellData(pages: [
          MarketplaceHomeScreen(showAdvertiserActions: true), MapScreen(), Stage6AuthGate(child: MessagesScreen()), AccountScreen(),
        ], items: [
          _NavItemData(label: 'العقارات', icon: Icons.home_outlined),
          _NavItemData(label: 'الخريطة', icon: Icons.map_outlined),
          _NavItemData(label: 'الرسائل', icon: Icons.chat_bubble_outline),
          _NavItemData(label: 'حسابي', icon: Icons.account_circle_outlined),
        ]);
      case 'regular':
      default:
        return _ShellData(
          pages: [
            MarketplaceHomeScreen(showAdvertiserActions: mode == 'advertiser'),
            const Stage6AuthGate(child: MessagesScreen()),
            const Stage6AuthGate(requireListingEligible: true, child: MyListingsScreen()),
            const AccountScreen(),
          ],
          items: const [
            _NavItemData(label: 'العقارات', icon: Icons.travel_explore_outlined),
            _NavItemData(label: 'الرسائل', icon: Icons.chat_bubble_outline),
            _NavItemData(label: 'إعلاناتي', icon: Icons.inventory_2_outlined),
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

