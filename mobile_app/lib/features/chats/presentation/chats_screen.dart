import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';

class ChatsScreen extends StatelessWidget {
  const ChatsScreen({super.key});

  static const _threads = <_ThreadData>[
    _ThreadData(
      id: 'seller-1',
      title: 'معلن عقار في حدة',
      subtitle: 'هل ترغب في تحديد موعد للمعاينة؟',
      time: 'الآن',
      unread: 2,
      icon: Icons.home_work_outlined,
    ),
    _ThreadData(
      id: 'project-1',
      title: 'فريق مشروع واحة النخيل',
      subtitle: 'تم إرسال تفاصيل الأسعار وخيارات الدفع.',
      time: 'أمس',
      unread: 0,
      icon: Icons.apartment_outlined,
    ),
    _ThreadData(
      id: 'support',
      title: 'خدمة العملاء',
      subtitle: 'نحن هنا لمساعدتك في أي استفسار.',
      time: '12:20',
      unread: 0,
      icon: Icons.support_agent_outlined,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('المحادثات'),
          actions: [
            IconButton(
              tooltip: 'بحث',
              onPressed: () {},
              icon: const Icon(Icons.search),
            ),
          ],
        ),
        body: ListView.separated(
          padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
          itemCount: _threads.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final thread = _threads[index];
            return Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(18),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                leading: CircleAvatar(
                  radius: 25,
                  backgroundColor: AppTheme.brandSoft,
                  child: Icon(thread.icon, color: AppTheme.brandStrong),
                ),
                title: Text(
                  thread.title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    thread.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      thread.time,
                      style: const TextStyle(
                        color: AppTheme.textMuted,
                        fontSize: 12,
                      ),
                    ),
                    if (thread.unread > 0) ...[
                      const SizedBox(height: 6),
                      Container(
                        constraints: const BoxConstraints(
                          minWidth: 22,
                          minHeight: 22,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          color: AppTheme.brand,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${thread.unread}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                onTap: () => context.push('/chats/${thread.id}'),
              ),
            );
          },
        ),
      ),
    );
  }
}

class ChatConversationScreen extends StatefulWidget {
  const ChatConversationScreen({required this.threadId, super.key});

  final String threadId;

  @override
  State<ChatConversationScreen> createState() => _ChatConversationScreenState();
}

class _ChatConversationScreenState extends State<ChatConversationScreen> {
  final _controller = TextEditingController();
  final List<_MessageData> _messages = [
    const _MessageData(
      text: 'مرحباً، هل العقار ما زال متاحاً؟',
      mine: true,
      time: '12:11',
    ),
    const _MessageData(
      text: 'نعم، ما زال متاحاً. يمكن ترتيب موعد للمعاينة.',
      mine: false,
      time: '12:13',
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('محادثة العقار'),
          actions: [
            IconButton(
              tooltip: 'معلومات الإعلان',
              onPressed: () {},
              icon: const Icon(Icons.info_outline),
            ),
          ],
        ),
        body: Column(
          children: [
            Container(
              margin: const EdgeInsets.fromLTRB(14, 8, 14, 4),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.brandSoft,
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Row(
                children: [
                  Icon(Icons.shield_outlined, color: AppTheme.brandStrong),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'لا ترسل بيانات دفع أو معلومات حساسة قبل التحقق من المعلن والعقار.',
                      style: TextStyle(fontSize: 12.5, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(14),
                itemCount: _messages.length,
                itemBuilder: (context, index) {
                  final message = _messages[index];
                  return Align(
                    alignment: message.mine
                        ? AlignmentDirectional.centerStart
                        : AlignmentDirectional.centerEnd,
                    child: Container(
                      constraints: const BoxConstraints(maxWidth: 290),
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                      decoration: BoxDecoration(
                        color: message.mine ? AppTheme.brand : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            message.text,
                            style: TextStyle(
                              color:
                                  message.mine ? Colors.white : Colors.black87,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            message.time,
                            style: TextStyle(
                              color: message.mine
                                  ? Colors.white70
                                  : AppTheme.textMuted,
                              fontSize: 10.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                child: Row(
                  children: [
                    IconButton.filled(
                      onPressed: _send,
                      icon: const Icon(Icons.send),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        minLines: 1,
                        maxLines: 4,
                        textInputAction: TextInputAction.newline,
                        decoration: const InputDecoration(
                          hintText: 'اكتب رسالة…',
                          prefixIcon: Icon(Icons.attach_file),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _send() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _messages.add(_MessageData(text: text, mine: true, time: 'الآن'));
      _controller.clear();
    });
  }
}

class _ThreadData {
  const _ThreadData({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.time,
    required this.unread,
    required this.icon,
  });

  final String id;
  final String title;
  final String subtitle;
  final String time;
  final int unread;
  final IconData icon;
}

class _MessageData {
  const _MessageData(
      {required this.text, required this.mine, required this.time});

  final String text;
  final bool mine;
  final String time;
}
