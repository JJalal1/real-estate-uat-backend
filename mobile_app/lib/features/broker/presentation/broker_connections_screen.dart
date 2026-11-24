import 'package:flutter/material.dart';
import '../../messages/presentation/messages_screen.dart';
import 'broker_workspaces.dart';

/// Conversations and customer followups share one destination.
class BrokerConnectionsScreen extends StatelessWidget {
  const BrokerConnectionsScreen({super.key});

  @override
  Widget build(BuildContext context) => DefaultTabController(
    length: 2,
    initialIndex: 1,
    child: BrokerScaffold(
      appBar: AppBar(
        title: const Text('الرسائل'),
        bottom: const TabBar(
          tabs: [Tab(text: 'المتابعة'), Tab(text: 'المحادثات')],
        ),
      ),
      body: const TabBarView(
        children: [
          BrokerCustomersScreen(embedded: true),
          MessagesScreen(embedded: true, compact: true),
        ],
      ),
    ),
  );
}
