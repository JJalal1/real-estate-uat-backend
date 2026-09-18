import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../account/data/auth_controller.dart';
import '../../account/domain/auth_user.dart';
import '../../account/presentation/p01/p01_account_screen.dart';
import '../../foundation/presentation/p02_home_screen.dart';
import '../../map/presentation/map_screen.dart';
import 'app_shell_screen.dart';

class P02AppShellScreen extends ConsumerStatefulWidget {
  const P02AppShellScreen({super.key});

  @override
  ConsumerState<P02AppShellScreen> createState() => _P02AppShellScreenState();
}

class _P02AppShellScreenState extends ConsumerState<P02AppShellScreen> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(authControllerProvider).asData?.value;

    if (_usesOperationalWorkspace(user)) {
      return const AppShellScreen();
    }

    const pages = <Widget>[
      P02HomeScreen(),
      MapScreen(enableListingCreation: false),
      P01AccountScreen(),
    ];

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        body: IndexedStack(index: _index, children: pages),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (value) => setState(() => _index = value),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'الرئيسية',
            ),
            NavigationDestination(
              icon: Icon(Icons.map_outlined),
              selectedIcon: Icon(Icons.map),
              label: 'العقارات',
            ),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'حسابي',
            ),
          ],
        ),
      ),
    );
  }

  bool _usesOperationalWorkspace(AuthUser? user) {
    if (user == null) return false;
    return user.isPlatformOwner ||
        user.roles.contains('super_admin') ||
        user.roles.contains('support_manager') ||
        user.roles.contains('support_agent');
  }
}
