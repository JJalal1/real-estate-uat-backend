import 'package:flutter/material.dart';
import '../../../core/widgets/ebroker_widgets.dart';
import '../../../core/widgets/ebroker_card_actions.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/widgets/app_components.dart';
import '../../account/data/auth_controller.dart';
import '../data/booking_repository.dart';
import '../domain/booking_models.dart';
import 'booking_request_sheet.dart';

typedef _BookingListKey = (String, bool, DateTime?, DateTime?);
final _bookingRowsProvider = FutureProvider.autoDispose.family<List<ViewingBooking>, _BookingListKey>((ref, key) {
  final repo = ref.watch(bookingRepositoryProvider);
  return key.$2 ? repo.managed(from: key.$3, before: key.$4) : repo.mine(from: key.$3, before: key.$4);
});

class BookingsScreen extends ConsumerStatefulWidget {
  const BookingsScreen({this.initialBookingId, this.embedded = false, this.initiallyToday = false, super.key});

  final int? initialBookingId;
  final bool embedded;
  final bool initiallyToday;

  @override
  ConsumerState<BookingsScreen> createState() => _BookingsScreenState();
}

class _BookingsScreenState extends ConsumerState<BookingsScreen> {
  bool _managed = false;
  late bool _today = widget.initiallyToday;
  _BookingListKey _key(bool managed) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final actor = ref.read(authControllerProvider).asData?.value;
    final scope = '${actor?.id}:${actor?.isActive}:${actor?.roles}:${actor?.permissions}';
    return (scope, managed, _today ? start : null, _today ? DateTime(now.year, now.month, now.day + 1) : null);
  }
  @override
  void didUpdateWidget(covariant BookingsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initiallyToday != widget.initiallyToday) _today = widget.initiallyToday;
  }

  List<ViewingBooking> _prioritized(List<ViewingBooking> items) {
    if (_today) {
      final now = DateTime.now();
      items = items.where((b) { final d = b.startsAt.toLocal(); return d.year == now.year && d.month == now.month && d.day == now.day; }).toList()
        ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    }
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
        appBar: widget.embedded ? null : AppBar(title: const Text('المعاينات والحجوزات')),
        body: auth.when(
          skipLoadingOnRefresh: false,
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => AppErrorState(message: friendlyApiError(error),
            onRetry: () => ref.invalidate(authControllerProvider)),
          data: (user) {
            if (user == null) {
              return Center(
                  child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const EbrokerIcon(Icons.calendar_month_outlined, size: 58),
                        const SizedBox(height: 12),
                        const Text(
                            'سجّل الدخول لطلب مواعيد المعاينة ومتابعة الحجوزات.',
                            textAlign: TextAlign.center),
                        const SizedBox(height: 14),
                        EbrokerFilledButton.icon(
                            onPressed: () => context.push('/auth'),
                            icon: const EbrokerIcon(Icons.login),
                            label: const Text('تسجيل الدخول')),
                      ])));
            }
            final canManaged = user.isPlatformOwner ||
                user.hasPermission('bookings.manage') ||
                user.hasPermission('developments.manage');
            if (!canManaged && _managed) _managed = false;
            final rows = ref.watch(_bookingRowsProvider(_key(_managed)));
            final retain = rows.hasValue && rows.hasError && isTransientApiFailure(rows.error!);
            return Column(children: [
              Padding(padding: const EdgeInsets.fromLTRB(16, 8, 16, 4), child: Wrap(spacing: 8, runSpacing: 8, children: [
                EbrokerChoiceChip(label: const Text('كل المعاينات'), selected: !_today, onSelected: (_) => setState(() => _today = false)),
                EbrokerChoiceChip(label: const Text('معاينات اليوم'), selected: _today, onSelected: (_) => setState(() => _today = true)),
              ])),
              if (canManaged)
                Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                    child: EbrokerSegmentedButton<bool>(
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
                skipError: retain,
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, _) => Center(
                    child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(mainAxisSize: MainAxisSize.min, children: [
                          Text(friendlyApiError(error),
                              textAlign: TextAlign.center),
                          const SizedBox(height: 10),
                          EbrokerOutlinedButton.icon(
                              onPressed: _refresh,
                              icon: const EbrokerIcon(Icons.refresh),
                              label: const Text('إعادة المحاولة'))
                        ]))),
                data: (items) {
                  final displayed = _prioritized(items);
                  return Column(children: [
                    AppRefreshStatus(loading: rows.isLoading,
                      error: retain ? friendlyApiError(rows.error!) : null, onRetry: _refresh),
                    Expanded(child: RefreshIndicator(
                      onRefresh: _refresh,
                      child: displayed.isEmpty
                        ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: [
                            const SizedBox(height: 140),
                            const EbrokerIcon(Icons.event_busy_outlined, size: 54),
                            const SizedBox(height: 12),
                            Center(child: Text(_today ? 'لا توجد معاينات اليوم.' : 'لا توجد طلبات معاينة حالياً.')),
                          ])
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 28),
                            physics: const AlwaysScrollableScrollPhysics(),
                            itemCount: displayed.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (context, index) {
                              final booking = displayed[index];
                              return _BookingCard(booking: booking,
                                highlighted: booking.id == widget.initialBookingId,
                                onAction: (action) => _action(booking, action));
                            }),
                    )),
                  ]);
                },
              )),
            ]);
          },
        ),
      ),
    );
  }

  Future<void> _refresh() async {
    if (ref.read(authControllerProvider).asData?.value == null) return;
    ref.invalidate(_bookingRowsProvider(_key(false)));
    ref.invalidate(_bookingRowsProvider(_key(true)));
    try {
      await ref.read(_bookingRowsProvider(_key(_managed)).future);
    } catch (_) {}
  }

  Future<void> _action(ViewingBooking booking, String action) async {
    if (action == 'conversation') {
      final threadId = booking.messageThreadId;
      if (threadId != null && mounted) await context.push('/messages/$threadId');
      return;
    }
    if (action == 'map' && booking.targetLatitude != null && booking.targetLongitude != null) {
      final coordinates = '${booking.targetLatitude},${booking.targetLongitude}';
      try {
        final opened = await launchUrl(Uri(scheme: 'geo', path: coordinates, queryParameters: {'q': coordinates}), mode: LaunchMode.externalApplication);
        if (!opened && mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر فتح الخريطة على هذا الجهاز.')));
      } catch (_) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('تعذر فتح الخريطة على هذا الجهاز.'))); }
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
                  EbrokerFilledButton(
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
                  avatar: EbrokerIcon(Icons.notifications_active_outlined, size: 16),
                  label: Text('من الإشعار'),
                ),
                const SizedBox(height: 6),
              ],
              Row(children: [
                Expanded(
                    child: Text(booking.targetTitle,
                        style: const TextStyle(fontWeight: FontWeight.w600))),
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
              const SizedBox(height: 10),
              EbrokerCardActions(actions: [
                if (booking.canConfirm) EbrokerCardAction(booking.canAcceptReschedule ? 'قبول الموعد الجديد' : 'تأكيد', () => onAction('confirm'), icon: Icons.check_circle_outline),
                if (booking.canComplete) EbrokerCardAction('تسجيل كمكتمل', () => onAction('complete'), icon: Icons.task_alt),
                if (booking.messageThreadId != null) EbrokerCardAction('فتح محادثة المعاينة', () => onAction('conversation'), icon: Icons.chat_bubble_outline),
                if (booking.targetLatitude != null && booking.targetLongitude != null) EbrokerCardAction('موقع العقار', () => onAction('map'), icon: Icons.location_on_outlined),
                if (booking.isActive && booking.canDecline) EbrokerCardAction('رفض', () => onAction('decline'), icon: Icons.cancel_outlined),
                if (booking.isActive && booking.canReschedule) EbrokerCardAction('تغيير الموعد', () => onAction('reschedule'), icon: Icons.schedule_outlined),
                if (booking.isActive && booking.canCancel) EbrokerCardAction('إلغاء', () => onAction('cancel'), icon: Icons.event_busy_outlined),
              ]),
              const SizedBox(height: 6),
              Text('المرجع: ${booking.reference}',
                  style: Theme.of(context).textTheme.bodySmall),
            ])));
  }
}
