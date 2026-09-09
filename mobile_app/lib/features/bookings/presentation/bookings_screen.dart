import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_components.dart';
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
  String _filter = 'active';

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

  List<ViewingBooking> _filtered(List<ViewingBooking> items) {
    return switch (_filter) {
      'action' => items.where(_needsUserAction).toList(growable: false),
      'done' => items.where((item) => !item.isActive).toList(growable: false),
      _ => items.where((item) => item.isActive).toList(growable: false),
    };
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: const AppAppBar(title: 'المعاينات'),
        body: auth.when(
          loading: () => const _BookingsSkeleton(),
          error: (_, __) => const AppErrorState(
            message: 'تعذر تحميل الحساب.',
          ),
          data: (user) {
            if (user == null) {
              return AppEmptyState(
                title: 'سجّل الدخول لمتابعة المعاينات',
                message:
                    'تقدر تطلب موعد من صفحة العقار ثم تتابع التأكيد والتغيير من هنا.',
                icon: Icons.calendar_month_outlined,
                actionLabel: 'تسجيل الدخول',
                onAction: () => context.push('/auth'),
              );
            }
            final canManaged = user.isPlatformOwner ||
                user.hasPermission('bookings.manage') ||
                user.hasPermission('developments.manage');
            if (!canManaged && _managed) _managed = false;
            final rows = ref.watch(_bookingRowsProvider(_managed));
            return Column(
              children: [
                if (canManaged)
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      AppLayout.compactPageGutter,
                      AppSpacing.s12,
                      AppLayout.compactPageGutter,
                      0,
                    ),
                    child: SegmentedButton<bool>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: false, label: Text('مواعيدي')),
                        ButtonSegment(
                          value: true,
                          label: Text('طلبات الإدارة'),
                        ),
                      ],
                      selected: {_managed},
                      onSelectionChanged: (value) {
                        setState(() {
                          _managed = value.first;
                          _filter = 'active';
                        });
                      },
                    ),
                  ),
                Expanded(
                  child: rows.when(
                    loading: () => const _BookingsSkeleton(),
                    error: (error, _) => AppErrorState(
                      message: friendlyApiError(error),
                      onRetry: _refresh,
                    ),
                    data: (items) {
                      final prioritized = _prioritized(items);
                      final displayed = _filtered(prioritized);
                      return RefreshIndicator(
                        onRefresh: _refresh,
                        child: CustomScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          slivers: [
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                  AppLayout.compactPageGutter,
                                  AppSpacing.s12,
                                  AppLayout.compactPageGutter,
                                  0,
                                ),
                                child: _BookingsOverview(items: prioritized),
                              ),
                            ),
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                  AppLayout.compactPageGutter,
                                  AppSpacing.s12,
                                  AppLayout.compactPageGutter,
                                  AppSpacing.s8,
                                ),
                                child: _BookingFilterBar(
                                  selected: _filter,
                                  items: prioritized,
                                  onChanged: (value) =>
                                      setState(() => _filter = value),
                                ),
                              ),
                            ),
                            if (displayed.isEmpty)
                              const SliverFillRemaining(
                                hasScrollBody: false,
                                child: AppEmptyState(
                                  title: 'لا توجد معاينات في هذه الحالة',
                                  message:
                                      'غيّر الفلتر لعرض المواعيد الأخرى.',
                                  icon: Icons.event_busy_outlined,
                                ),
                              )
                            else
                              SliverPadding(
                                padding: const EdgeInsetsDirectional.fromSTEB(
                                  AppLayout.compactPageGutter,
                                  AppSpacing.s4,
                                  AppLayout.compactPageGutter,
                                  AppSpacing.s40,
                                ),
                                sliver: SliverList.separated(
                                  itemCount: displayed.length,
                                  separatorBuilder: (_, __) => const SizedBox(
                                    height: AppSpacing.s12,
                                  ),
                                  itemBuilder: (context, index) {
                                    final booking = displayed[index];
                                    return _BookingCard(
                                      booking: booking,
                                      highlighted: booking.id ==
                                          widget.initialBookingId,
                                      onAction: (action) =>
                                          _action(booking, action),
                                    );
                                  },
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
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
      if (threadId != null && mounted) {
        await context.push('/messages/$threadId');
      }
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم تحديث المعاينة.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyApiError(error))),
      );
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
          decoration: InputDecoration(labelText: label),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.length < 2) return null;
    return value;
  }
}

class _BookingsOverview extends StatelessWidget {
  const _BookingsOverview({required this.items});

  final List<ViewingBooking> items;

  @override
  Widget build(BuildContext context) {
    final actionCount = items.where(_needsUserAction).length;
    final activeCount = items.where((item) => item.isActive).length;
    return AppSurface(
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(AppRadii.control),
            ),
            child: Icon(
              actionCount > 0
                  ? Icons.event_available_outlined
                  : Icons.calendar_month_outlined,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: AppSpacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  actionCount > 0
                      ? 'عندك $actionCount موعد يحتاج قرارك'
                      : 'معايناتك مرتبة',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.s4),
                Text(
                  '$activeCount موعد نشط • ${items.length} إجمالي',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BookingFilterBar extends StatelessWidget {
  const _BookingFilterBar({
    required this.selected,
    required this.items,
    required this.onChanged,
  });

  final String selected;
  final List<ViewingBooking> items;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final counts = <String, int>{
      'active': items.where((item) => item.isActive).length,
      'action': items.where(_needsUserAction).length,
      'done': items.where((item) => !item.isActive).length,
    };
    final labels = <String, String>{
      'active': 'النشطة',
      'action': 'تحتاج إجراء',
      'done': 'المنتهية',
    };
    return SizedBox(
      height: 42,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: labels.length,
        separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.s8),
        itemBuilder: (context, index) {
          final key = labels.keys.elementAt(index);
          return ChoiceChip(
            selected: selected == key,
            label: Text('${labels[key]} (${counts[key]})'),
            onSelected: (_) => onChanged(key),
          );
        },
      ),
    );
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
    final action = _nextBookingAction(booking);
    return AppSurface(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding:
                const EdgeInsetsDirectional.all(AppLayout.surfacePadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        booking.targetTitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s8),
                    AppStatusBadge(
                      label: booking.statusLabel,
                      tone: _bookingTone(booking),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.s12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.schedule_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: AppSpacing.s8),
                    Expanded(
                      child: Text(
                        '${_weekdayLabel(start.weekday)} • ${_formatDateTime(start)}',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                  ],
                ),
                if (booking.targetAddress != null) ...[
                  const SizedBox(height: AppSpacing.s8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.location_on_outlined, size: 20),
                      const SizedBox(width: AppSpacing.s8),
                      Expanded(child: Text(booking.targetAddress!)),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.s8),
                Text(
                  booking.isRequester
                      ? 'المستضيف: ${booking.hostName ?? 'سيتم تحديده عند التأكيد'}'
                      : 'طالب المعاينة: ${booking.requesterName}',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (highlighted) ...[
                  const SizedBox(height: AppSpacing.s8),
                  const AppStatusBadge(
                    label: 'تم فتح هذا الموعد من الإشعار',
                    tone: AppStatusTone.info,
                    icon: Icons.notifications_active_outlined,
                  ),
                ],
                if (action != null) ...[
                  const SizedBox(height: AppSpacing.s12),
                  AppInlineMessage(
                    title: action.$1,
                    message: action.$2,
                    tone: action.$3,
                  ),
                ],
                if (booking.requesterNote?.isNotEmpty == true) ...[
                  const SizedBox(height: AppSpacing.s8),
                  Text('ملاحظة الطلب: ${booking.requesterNote}'),
                ],
                if (booking.hostNote?.isNotEmpty == true) ...[
                  const SizedBox(height: AppSpacing.s8),
                  Text('رد المستضيف: ${booking.hostNote}'),
                ],
                if (booking.cancellationReason?.isNotEmpty == true) ...[
                  const SizedBox(height: AppSpacing.s8),
                  Text('سبب الإلغاء: ${booking.cancellationReason}'),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsetsDirectional.all(AppSpacing.s8),
            child: Wrap(
              spacing: AppSpacing.s8,
              runSpacing: AppSpacing.s8,
              children: [
                if (booking.canConfirm)
                  FilledButton.tonalIcon(
                    onPressed: () => onAction('confirm'),
                    icon: const Icon(Icons.check_circle_outline),
                    label: Text(
                      booking.canAcceptReschedule
                          ? 'قبول الموعد الجديد'
                          : 'تأكيد الموعد',
                    ),
                  ),
                if (booking.canReschedule)
                  OutlinedButton.icon(
                    onPressed: () => onAction('reschedule'),
                    icon: const Icon(Icons.schedule_outlined),
                    label: const Text('تغيير الموعد'),
                  ),
                if (booking.messageThreadId != null)
                  OutlinedButton.icon(
                    onPressed: () => onAction('conversation'),
                    icon: const Icon(Icons.chat_bubble_outline),
                    label: const Text('المحادثة'),
                  ),
                if (booking.canDecline)
                  TextButton.icon(
                    onPressed: () => onAction('decline'),
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('رفض'),
                  ),
                if (booking.canCancel)
                  TextButton.icon(
                    onPressed: () => onAction('cancel'),
                    icon: const Icon(Icons.event_busy_outlined),
                    label: const Text('إلغاء'),
                  ),
                if (booking.canComplete)
                  FilledButton.tonalIcon(
                    onPressed: () => onAction('complete'),
                    icon: const Icon(Icons.task_alt),
                    label: const Text('تسجيل كمكتمل'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BookingsSkeleton extends StatelessWidget {
  const _BookingsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsetsDirectional.all(AppLayout.compactPageGutter),
      children: const [
        AppSkeleton(height: 116, radius: AppRadii.card),
        SizedBox(height: AppSpacing.s12),
        AppSkeleton(height: 42),
        SizedBox(height: AppSpacing.s12),
        AppSkeleton(height: 220, radius: AppRadii.card),
        SizedBox(height: AppSpacing.s12),
        AppSkeleton(height: 220, radius: AppRadii.card),
      ],
    );
  }
}

bool _needsUserAction(ViewingBooking booking) =>
    booking.canConfirm ||
    booking.canDecline ||
    (booking.awaitingRequesterConfirmation && booking.isRequester);

(String, String, AppStatusTone)? _nextBookingAction(ViewingBooking booking) {
  if (booking.awaitingRequesterConfirmation && booking.isRequester) {
    return (
      'مطلوب منك قرار',
      'المعلن اقترح موعدًا جديدًا. راجعه ثم وافق أو غيّر الموعد.',
      AppStatusTone.warning,
    );
  }
  if (booking.canConfirm) {
    return (
      'مطلوب منك تأكيد',
      'راجع الوقت والمكان ثم أكد الموعد إذا يناسبك.',
      AppStatusTone.warning,
    );
  }
  if (booking.isActive) {
    return (
      'الخطوة التالية',
      'احتفظ بالموعد وتابع أي تغيير من هنا أو من المحادثة المرتبطة.',
      AppStatusTone.info,
    );
  }
  return null;
}

AppStatusTone _bookingTone(ViewingBooking booking) {
  if (_needsUserAction(booking)) return AppStatusTone.warning;
  if (booking.canComplete) return AppStatusTone.success;
  if (booking.isActive) return AppStatusTone.info;
  return AppStatusTone.neutral;
}

String _formatDateTime(DateTime value) {
  final date =
      '${value.year}/${value.month.toString().padLeft(2, '0')}/${value.day.toString().padLeft(2, '0')}';
  final time =
      '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  return '$date • $time';
}

String _weekdayLabel(int weekday) => switch (weekday) {
      DateTime.monday => 'الاثنين',
      DateTime.tuesday => 'الثلاثاء',
      DateTime.wednesday => 'الأربعاء',
      DateTime.thursday => 'الخميس',
      DateTime.friday => 'الجمعة',
      DateTime.saturday => 'السبت',
      _ => 'الأحد',
    };
