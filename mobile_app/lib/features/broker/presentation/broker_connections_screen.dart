import 'package:flutter/material.dart';
import '../../messages/presentation/messages_screen.dart';
import 'broker_workspaces.dart';

/// Customer followups and conversations share one destination; deals stay in Work.
class BrokerConnectionsScreen extends StatelessWidget {
  const BrokerConnectionsScreen({super.key});
  @override
  Widget build(BuildContext context) => DefaultTabController(length: 2, child: BrokerScaffold(
    appBar: AppBar(title: const Text('إدارة العملاء'), bottom: const TabBar(tabs: [Tab(text: 'إدارة العملاء'), Tab(text: 'المحادثات')])),
    body: const TabBarView(children: [BrokerCustomersScreen(embedded: true), MessagesScreen(embedded: true)]),
  ));
}
