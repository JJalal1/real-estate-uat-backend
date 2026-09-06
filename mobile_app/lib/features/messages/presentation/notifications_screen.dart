import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../data/message_repository.dart';
import '../domain/message_models.dart';
import 'conversation_screen.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});
  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  bool _loading = true;
  String? _error;
  List<AppNotificationItem> _items = const [];
  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    try {
      final items = await ref.read(messageRepositoryProvider).notifications();
      if (!mounted) {
        return;
      }
      setState(() {
        _items = items;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _error = friendlyApiError(error);
      });
    }
  }

  Future<void> _readAll() async {
    await ref.read(messageRepositoryProvider).readAllNotifications();
    await _load();
  }

  Future<void> _open(AppNotificationItem item) async {
    if (!item.isRead) {
      await ref.read(messageRepositoryProvider).readNotification(item.id);
    }
    if (!mounted) {
      return;
    }
    var openedDestination = true;
    if (item.entityType == 'message_thread' && item.entityId != null) {
      await Navigator.of(context).push<void>(MaterialPageRoute<void>(
          builder: (_) => ConversationScreen(threadId: item.entityId!)));
    } else if (item.entityType == 'account_verification_profile' ||
        item.entityType == 'account_verification') {
      await context.push<void>('/account-verification');
    } else if (item.entityType == 'support_case' && item.entityId != null) {
      await context.push<void>('/support?case=${item.entityId}');
    } else if (item.entityType == 'support_task') {
      await context.push<void>('/support/workspace');
    } else if (item.entityType == 'viewing_booking') {
      await context.push<void>('/bookings');
    } else if (item.entityType == 'property' && item.entityId != null) {
      await context.push<void>('/properties/${item.entityId}');
    } else if (item.entityType == 'service_order') {
      await context.push<void>('/services');
    } else {
      openedDestination = false;
    }
    if (!openedDestination && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تمت قراءة الإشعار ولا توجد صفحة مرتبطة به.')),
      );
    }
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('الإشعارات'), actions: [
          TextButton(
              onPressed: _items.any((e) => !e.isRead) ? _readAll : null,
              child: const Text('قراءة الكل'))
        ]),
        body: RefreshIndicator(
            onRefresh: _load,
            child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  if (_loading)
                    const Padding(
                        padding: EdgeInsets.all(36),
                        child: Center(child: CircularProgressIndicator()))
                  else if (_error != null)
                    Card(
                        child: Padding(
                            padding: const EdgeInsets.all(18),
                            child: Text(_error!)))
                  else if (_items.isEmpty)
                    const Card(
                        child: Padding(
                            padding: EdgeInsets.all(22),
                            child: Text('لا توجد إشعارات بعد.')))
                  else
                    ..._items.map((item) => Card(
                            child: ListTile(
                          leading: Icon(item.isRead
                              ? Icons.notifications_none
                              : Icons.notifications_active_outlined),
                          title: Text(item.title,
                              style: TextStyle(
                                  fontWeight: item.isRead
                                      ? FontWeight.w600
                                      : FontWeight.w900)),
                          subtitle: item.body == null ? null : Text(item.body!),
                          onTap: () => _open(item),
                        ))),
                ])),
      ),
    );
  }
}
