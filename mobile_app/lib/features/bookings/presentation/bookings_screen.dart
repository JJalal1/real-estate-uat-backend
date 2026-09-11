import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../account/data/auth_controller.dart';
import '../data/booking_repository.dart';
import '../domain/booking_models.dart';
import 'booking_request_sheet.dart';

final _bookingRowsProvider = FutureProvider.autoDispose
    .family<List<ViewingBooking>, bool>((ref, managed) {
  final repo = ref.watch(bookingRepositoryProvider);
  return managed ? repo.managed() : repo.mine();
});

class BookingsScreen extends ConsumerStatefulWidget {
  const BookingsScreen({this.initialBookingId, super.key});

  final int? initialBookingId;

  @override
  ConsumerState<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends ConsumerState<BookingsScreen> {
  bool _managed = false;

  List<ViewingBooking> _prioritized(List<ViewingBooking> items) {
    final id = widget.initialBookingId;
    if (id == null) return items;
    final index = items.indexWhere((item) => item.id == id);
    if (index <= 0) return items;
    return <ViewingBooking>[
      items[index],
      ...items.take(index),
      ...items.skip(index + 1),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('المعاينات والحجوزات')),
        body: auth.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) => const Center(child: Text('تعذر تحميل الحساب.')),
          data: (user) {
            if (user == null) {
              return Center(
                  child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.calendar_month_outlined, size: 58),
                        const SizedBox(height: 12),
                        const Text(
                            'سجّل الدخول لطلب مواعيد المعاينة ومتابعة الحجوزات.',
                            textAlign: TextAlign.center),
                        const SizedBox(height: 14),
                        FilledButton.icon(
                            onPressed: () => context.push('/auth'),
                            icon: const Icon(Icons.login),
                            label: const Text('تسجيل الدخول')),
                      ])));
            }
            final canManaged = user.isPlatformOwner ||
                user.hasPermission('bookings.manage') ||
                user.hasPermission('developments.manage');
            if (!canManaged && _managed) _managed = false;
            final rows = ref.watch(_bookingRowsProvider(_managed));
            return Column(children: [
              if (canManaged)
                Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                    child: SegmentedButton<bool>(
                        showSelectedIcon: false,
                        segments: const [
                          ButtonSegment(value: false, label: Text('مواعيدي')),
                          ButtonSegment(value: true, label: Text('طلبات الإدارة'))
                        ],
                        selected: {_managed},
                        onSelectionChanged: (value) =>
                            setState(() => _managed = value.first))),
              Expanded(
                  child: rows.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(
                    child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(friendlyApiError(error),
                              textAlign: TextAlign.center),
                          const SizedBox(height: 10),
                          OutlinedButton.icon(
                              onPressed: _refresh,
                              icon: const Icon(Icons.refresh),
                              label: const Text('إعادة المحاولة'))
                        ]))),
                data: (items) {
                  final displayed = _prioritized(items);
                  return RefreshIndicator(
                      onRefresh: _refresh,
                      child: displayed.isEmpty
                          ? ListView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: const [
                                  SizedBox(height: 140),
                                  Icon(Icons.event_busy_outlined, size: 54),
                                  SizedBox(height: 12),
                                  Center(
                                      child: Text('لا توجد طلبات معاينة حالياً.'))
                                ])
                          : ListView.separated(
                              padding:
                                  const EdgeInsets.fromLTRB(16, 10, 16, 28),
                              physics: const AlwaysScrollableScrollPhysics(),
                              itemCount: displayed.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final booking = displayed[index];
                                return _BookingCard(
                                  booking: booking,
                                  highlighted:
                                      booking.id == widget.initialBookingId,
                                  onAction: (action) =>
                                      _action(booking, action),
                                );
                              }));
                },
              )),
            ]);
          },
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    ref.invalidate(_bookingRowsProvider(false));
    ref.invalidate(_bookingRowsProvider(true));
    try {
      await ref.read(_bookingRowsProvider(_managed).future);
    } catch (_) {}
  }

  Future<void> _action(ViewingBooking booking, String action) async {
    if (action == 'conversation') {
      final threadId = booking.messageThreadId;
      if (threadId != null && mounted) await context.push('/messages/$threadId');
      return;
    }
    try {
      final repo = ref.read(bookingRepositoryProvider);
      if (action == 'confirm') await repo.confirm(booking.id);
      if (action == 'decline') {
        final note = await _textDialog('رفض الطلب', 'سبب الرفض');
        if (note == null) return;
        await repo.decline(booking.id, note);
      }
      if (action == 'cancel') {
        final reason = await _textDialog('إلغاء الموعد', 'سبب الإلغاء');
        if (reason == null) return;
        await repo.cancel(booking.id, reason);
      }
      if (action == 'reschedule') {
        if (!mounted) return;
        final changed =
            await BookingRequestSheet.showForReschedule(context, booking);
        if (changed == null) return;
      }
      if (action == 'complete') await repo.complete(booking.id);
      if (!mounted) return;
      await _refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('تم تحديث الحجز.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
    }
  }

  Future<String?> _textDialog(String title, String label) async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(title),
                content: TextField(
                    controller: controller,
                    maxLength: 1500,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(labelText: label)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('إلغاء')),
                  FilledButton(
                      onPressed: () =>
                          Navigator.pop(context, controller.text.trim()),
                      child: const Text('حفظ'))
                ]));
    controller.dispose();
    if (value == null || value.length < 2) return null;
    return value;
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({
    required this.booking,
    required this.onAction,
    this.highlighted = false,
  });

  final ViewingBooking booking;
  final ValueChanged<String> onAction;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final start = booking.startsAt.toLocal();
    final date =
        "${start.year}/${start.month.toString().padLeft(2, '0')}/${start.day.toString().padLeft(2, '0')} - ${start.hour.toString().padLeft(2, '0')}:${start.minute.toString().padLeft(2, '0')}";
    return Card(
        elevation: highlighted ? 3 : null,
        child: Padding(
            padding: const EdgeInsets.all(14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (highlighted) ...[
                const Chip(
                  avatar: Icon(Icons.notifications_active_outlined, size: 16),
                  label: Text('من الإشعار'),
                ),
                const SizedBox(height: 6),
              ],
              Row(children: [
                Expanded(
                    child: Text(booking.targetTitle,
                        style: const TextStyle(fontWeight: FontWeight.w900))),
                Chip(label: Text(booking.statusLabel))
              ]),
              const SizedBox(height: 5),
              Text('${booking.targetLabel} • $date'),
              if (booking.targetAddress != null) ...[
                const SizedBox(height: 4),
                Text(booking.targetAddress!,
                    style: const TextStyle(color: Colors.black54))
              ],
              const SizedBox(height: 5),
              Text(booking.isRequester
                  ? 'المستضيف: ${booking.hostName ?? 'سيتم تعيينه عند التأكيد'}'
                  : 'طالب المعاينة: ${booking.requesterName}'),
              if (booking.awaitingRequesterConfirmation && booking.isRequester) ...[
                const SizedBox(height: 7),
                const Text(
                    'المعلن اقترح موعداً جديداً. راجعه ثم وافق أو غيّر الموعد.',
                    style: TextStyle(fontWeight: FontWeight.w700)),
              ],
              if (booking.requesterNote?.isNotEmpty == true) ...[
                const SizedBox(height: 7),
                Text('ملاحظة الطلب: ${booking.requesterNote}')
              ],
              if (booking.hostNote?.isNotEmpty == true) ...[
                const SizedBox(height: 7),
                Text('رد المستضيف: ${booking.hostNote}')
              ],
              if (booking.cancellationReason?.isNotEmpty == true) ...[
                const SizedBox(height: 7),
                Text('سبب الإلغاء: ${booking.cancellationReason}')
              ],
              if (booking.messageThreadId != null) ...[
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => onAction('conversation'),
                  icon: const Icon(Icons.chat_bubble_outline),
                  label: const Text('فتح محادثة المعاينة'),
                ),
              ],
              if (booking.isActive) ...[
                const SizedBox(height: 10),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  if (booking.canConfirm)
                    FilledButton.icon(
                        onPressed: () => onAction('confirm'),
                        icon: const Icon(Icons.check_circle_outline),
                        label: Text(booking.canAcceptReschedule
                            ? 'قبول الموعد الجديد'
                            : 'تأكيد')),
                  if (booking.canDecline)
                    OutlinedButton.icon(
                        onPressed: () => onAction('decline'),
                        icon: const Icon(Icons.cancel_outlined),
                        label: const Text('رفض')),
                  if (booking.canReschedule)
                    OutlinedButton.icon(
                        onPressed: () => onAction('reschedule'),
                        icon: const Icon(Icons.schedule_outlined),
                        label: const Text('تغيير الموعد')),
                  if (booking.canCancel)
                    OutlinedButton.icon(
                        onPressed: () => onAction('cancel'),
                        icon: const Icon(Icons.event_busy_outlined),
                        label: const Text('إلغاء')),
                ])
              ],
              if (booking.canComplete) ...[
                const SizedBox(height: 10),
                FilledButton.tonalIcon(
                    onPressed: () => onAction('complete'),
                    icon: const Icon(Icons.task_alt),
                    label: const Text('تسجيل كمكتمل'))
              ],
              const SizedBox(height: 6),
              Text('المرجع: ${booking.reference}',
                  style: Theme.of(context).textTheme.bodySmall),
            ])));
  }
}
