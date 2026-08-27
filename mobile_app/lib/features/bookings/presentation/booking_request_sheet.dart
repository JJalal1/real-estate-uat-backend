import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../data/booking_repository.dart';
import '../domain/booking_models.dart';

class BookingRequestSheet extends ConsumerStatefulWidget {
  const BookingRequestSheet._(
      {required this.targetType,
      required this.targetId,
      required this.title,
      this.reschedule});
  final String targetType;
  final int targetId;
  final String title;
  final ViewingBooking? reschedule;

  static Future<bool?> showForProperty(BuildContext context,
          {required int propertyId, required String title}) =>
      showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => BookingRequestSheet._(
            targetType: 'property', targetId: propertyId, title: title),
      );

  static Future<bool?> showForDevelopmentUnit(BuildContext context,
          {required int unitId, required String title}) =>
      showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => BookingRequestSheet._(
            targetType: 'development_unit', targetId: unitId, title: title),
      );

  static Future<bool?> showForReschedule(
          BuildContext context, ViewingBooking booking) =>
      showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => BookingRequestSheet._(
            targetType: booking.targetType,
            targetId: booking.targetId,
            title: booking.targetTitle,
            reschedule: booking),
      );

  @override
  ConsumerState<BookingRequestSheet> createState() =>
      _BookingRequestSheetState();
}

class _BookingRequestSheetState extends ConsumerState<BookingRequestSheet> {
  late DateTime _date;
  late TimeOfDay _time;
  int _duration = 60;
  final _note = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.reschedule?.startsAt.toLocal() ??
        DateTime.now().add(const Duration(days: 1));
    _date = DateTime(initial.year, initial.month, initial.day);
    _time = TimeOfDay(hour: initial.hour, minute: initial.minute);
    if (widget.reschedule != null) {
      final minutes = widget.reschedule!.endsAt
          .difference(widget.reschedule!.startsAt)
          .inMinutes;
      if ([30, 60, 90, 120].contains(minutes)) _duration = minutes;
      _note.text = widget.reschedule!.requesterNote ?? '';
    }
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.fromLTRB(18, 12, 18, 22 + bottom),
        child: SingleChildScrollView(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                    child: Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                            color: Colors.black12,
                            borderRadius: BorderRadius.circular(999)))),
                const SizedBox(height: 16),
                Text(
                    widget.reschedule == null
                        ? 'طلب موعد معاينة'
                        : 'تغيير موعد المعاينة',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 5),
                Text(widget.title),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(
                      child: OutlinedButton.icon(
                          onPressed: _pickDate,
                          icon: const Icon(Icons.date_range_outlined),
                          label: Text(
                              '${_date.year}/${_date.month}/${_date.day}'))),
                  const SizedBox(width: 8),
                  Expanded(
                      child: OutlinedButton.icon(
                          onPressed: _pickTime,
                          icon: const Icon(Icons.schedule_outlined),
                          label: Text(_time.format(context)))),
                ]),
                const SizedBox(height: 10),
                DropdownButtonFormField<int>(
                  value: _duration,
                  decoration: const InputDecoration(labelText: 'مدة المعاينة'),
                  items: const [30, 60, 90, 120]
                      .map((value) => DropdownMenuItem(
                          value: value, child: Text('$value دقيقة')))
                      .toList(),
                  onChanged: _busy
                      ? null
                      : (value) {
                          if (value != null) setState(() => _duration = value);
                        },
                ),
                const SizedBox(height: 10),
                TextField(
                    controller: _note,
                    minLines: 2,
                    maxLines: 4,
                    maxLength: 2000,
                    decoration: const InputDecoration(
                        labelText: 'ملاحظة اختيارية',
                        hintText: 'مثلاً: أفضّل التواصل قبل الموعد بنصف ساعة')),
                const SizedBox(height: 8),
                FilledButton.icon(
                    onPressed: _busy ? null : _submit,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.event_available_outlined),
                    label: Text(widget.reschedule == null
                        ? 'إرسال الطلب'
                        : 'حفظ الموعد الجديد')),
              ]),
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
        context: context,
        initialDate: _date.isBefore(now) ? now : _date,
        firstDate: now,
        lastDate: now.add(const Duration(days: 120)));
    if (picked != null && mounted) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(context: context, initialTime: _time);
    if (picked != null && mounted) setState(() => _time = picked);
  }

  Future<void> _submit() async {
    final localStart =
        DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);
    final localEnd = localStart.add(Duration(minutes: _duration));
    final payload = <String, dynamic>{
      'starts_at': localStart.toUtc().toIso8601String(),
      'ends_at': localEnd.toUtc().toIso8601String(),
      'timezone': 'UTC',
      if (_note.text.trim().isNotEmpty) 'note': _note.text.trim()
    };
    setState(() => _busy = true);
    try {
      final repo = ref.read(bookingRepositoryProvider);
      if (widget.reschedule != null) {
        await repo.reschedule(widget.reschedule!.id, payload);
      } else if (widget.targetType == 'property') {
        await repo.requestProperty(widget.targetId, payload);
      } else {
        await repo.requestUnit(widget.targetId, payload);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(widget.reschedule == null
              ? 'تم إرسال طلب المعاينة.'
              : 'تم تحديث الموعد ويحتاج إلى تأكيد جديد.')));
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
      setState(() => _busy = false);
    }
  }
}
