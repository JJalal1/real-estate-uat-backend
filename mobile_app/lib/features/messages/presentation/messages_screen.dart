import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../data/message_repository.dart';
import '../domain/message_models.dart';
import 'conversation_screen.dart';

class MessagesScreen extends ConsumerStatefulWidget {
  const MessagesScreen({super.key});
  @override
  ConsumerState<MessagesScreen> createState() => _MessagesScreenState();
}

class _MessagesScreenState extends ConsumerState<MessagesScreen> {
  bool _loading = true;
  int? _seenRevision;
  String? _error;
  List<MessageThreadSummary> _items = const [];

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final items = await ref.read(messageRepositoryProvider).threads();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = friendlyApiError(error);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final revision = ref.watch(messageDataRevisionProvider);
    if (_seenRevision == null) {
      _seenRevision = revision;
    } else if (_seenRevision != revision) {
      _seenRevision = revision;
      Future<void>.microtask(_load);
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('الرسائل')),
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
                        child: Text(
                            'لا توجد محادثات بعد. افتح إعلاناً منشوراً واضغط مراسلة المعلن.')))
              else
                ..._items.map((item) => Card(
                      child: ListTile(
                        leading: CircleAvatar(
                            child: Text(item.otherUserName.isEmpty
                                ? '?'
                                : item.otherUserName.substring(0, 1))),
                        title: Text(item.otherUserName,
                            style:
                                const TextStyle(fontWeight: FontWeight.w800)),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.lastMessagePreview ??
                                    item.propertyTitle ??
                                    'محادثة خاصة',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (item.isPropertyUnavailable) ...[
                                const SizedBox(height: 4),
                                const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.info_outline, size: 15),
                                    SizedBox(width: 4),
                                    Flexible(
                                      child: Text(
                                        'الإعلان غير منشور حالياً — سجل المحادثة محفوظ',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ),
                        trailing: item.unreadCount > 0
                            ? CircleAvatar(
                                radius: 13,
                                child: Text('${item.unreadCount}',
                                    style: const TextStyle(fontSize: 11)))
                            : const Icon(Icons.chevron_left),
                        onTap: () async {
                          await Navigator.of(context).push<void>(
                              MaterialPageRoute<void>(
                                  builder: (_) =>
                                      ConversationScreen(threadId: item.id)));
                          await _load();
                        },
                      ),
                    )),
            ],
          ),
        ),
      ),
    );
  }
}
