import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../data/message_repository.dart';
import '../domain/message_models.dart';
import '../domain/notification_destination.dart';

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
  bool _actionPending = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    try {
      final items = await ref.read(messageRepositoryProvider).notifications();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = friendlyApiError(error);
      });
    }
  }

  Future<void> _readAll() async {
    if (_actionPending) return;
    setState(() => _actionPending = true);
    try {
      await ref.read(messageRepositoryProvider).readAllNotifications();
      if (mounted) await _load();
    } catch (error) {
      _showActionError(error);
    } finally {
      if (mounted) setState(() => _actionPending = false);
    }
  }

  Future<void> _open(AppNotificationItem item) async {
    if (_actionPending) return;
    setState(() => _actionPending = true);
    try {
      await _openDestination(item);
    } catch (error) {
      _showActionError(error);
    } finally {
      if (mounted) setState(() => _actionPending = false);
    }
  }

  void _showActionError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(friendlyApiError(error))),
    );
  }

  Future<void> _openDestination(AppNotificationItem item) async {
    if (!item.isRead) {
      await ref.read(messageRepositoryProvider).readNotification(item.id);
    }
    if (!mounted) return;

    final destination = notificationDestination(item);
    if (destination != null) {
      await context.push<void>(destination);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تمت قراءة الإشعار ولا توجد صفحة مرتبطة به.')),
      );
    }
    if (mounted) await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('الإشعارات'), actions: [
          TextButton(
              onPressed: !_actionPending && _items.any((e) => !e.isRead)
                  ? _readAll
                  : null,
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
                          trailing: const Icon(Icons.chevron_left),
                          onTap: _actionPending ? null : () => _open(item),
                        ))),
                ])),
      ),
    );
  }
}
