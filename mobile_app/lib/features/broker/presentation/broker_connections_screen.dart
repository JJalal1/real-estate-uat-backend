import 'package:flutter/material.dart';
import 'broker_workspaces.dart';

class BrokerConnectionsScreen extends StatelessWidget {
  const BrokerConnectionsScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const BrokerCustomersScreen(includeOtherThreads: true);
}
