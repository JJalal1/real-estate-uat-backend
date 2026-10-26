import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/platform/stage5_media_picker.dart';
import '../data/property_repository.dart';
import '../domain/listing_account_draft.dart';

/// Visible only for existing editable drafts when explicitly enabled in a
/// validated UAT build. The server gate remains authoritative.
class ListingVideoUploadPanel extends ConsumerStatefulWidget {
  const ListingVideoUploadPanel({required this.propertyId, super.key});
  final int propertyId;

  @override
  ConsumerState<ListingVideoUploadPanel> createState() => _ListingVideoUploadPanelState();
}

class _ListingVideoUploadPanelState extends ConsumerState<ListingVideoUploadPanel> {
  final Stage5MediaPicker _picker = const Stage5MediaPicker();
  String? _selectedPath;
  String? _uploadId;
  String? _error;
  String _status = 'not_uploaded';
  double _progress = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_refresh);
  }

  Future<void> _refresh() async {
    try {
      final value = await ref.read(propertyRepositoryProvider).listingVideoStatus(widget.propertyId);
      if (!mounted) return;
      setState(() {
        _status = value?['status']?.toString() ?? 'not_uploaded';
      });
    } catch (_) {
      // Gate may be closed on UAT. No retry loop or background polling.
    }
  }

  Future<void> _choose() async {
    if (_busy) return;
    try {
      final path = await _picker.pickVideo();
      if (!mounted || path == null) return;
      setState(() {
        _selectedPath = path;
        _uploadId = newListingDraftKey();
        _status = 'selected';
        _error = null;
        _progress = 0;
      });
    } on PlatformException catch (e) {
      if (mounted) setState(() => _error = e.message ?? 'تعذر اختيار الفيديو');
    }
  }

  Future<void> _upload() async {
    final path = _selectedPath, key = _uploadId;
    if (_busy || path == null || key == null || !File(path).existsSync()) return;
    setState(() { _busy = true; _error = null; _progress = 0; });
    try {
      final result = await ref.read(propertyRepositoryProvider).uploadListingVideo(
        widget.propertyId, path: path, uploadId: key,
        onSendProgress: (sent, total) {
          if (mounted && total > 0) setState(() => _progress = sent / total);
        },
      );
      if (mounted) {
        setState(() { _status = result['status']?.toString() ?? 'uploaded'; });
      }
      await _picker.clearTemporaryFiles([path]);
      if (mounted) setState(() { _selectedPath = null; _uploadId = null; });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyApiError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      await ref.read(propertyRepositoryProvider).deleteListingVideo(widget.propertyId);
      if (mounted) setState(() { _status = 'not_uploaded'; });
    } catch (e) {
      if (mounted) setState(() => _error = friendlyApiError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = switch (_status) {
      'uploaded' => 'تم الرفع، بانتظار المعالجة',
      'processing' => 'جارٍ معالجة الفيديو',
      'ready' => 'الفيديو جاهز',
      'failed' => 'تعذرت المعالجة؛ أعد اختيار الفيديو بعد إزالة الملف',
      'selected' => 'فيديو جاهز للرفع',
      _ => 'لم تضف فيديو بعد',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('فيديو الإعلان (اختياري)', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text('فيديو واحد حتى 50 ميجابايت و90 ثانية. لا يُعرض قبل اكتمال المعالجة.'),
          const SizedBox(height: 8),
          Text(label, key: const ValueKey('listing-video-status')),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (_busy) LinearProgressIndicator(value: _progress > 0 && _progress < 1 ? _progress : null),
          TextButton.icon(onPressed: _busy ? null : _choose,
            icon: const Icon(Icons.video_file_outlined), label: const Text('اختيار فيديو')),
          if (_selectedPath != null)
            FilledButton(onPressed: _busy ? null : _upload, child: const Text('رفع الفيديو')),
          if (_status != 'not_uploaded' && _status != 'selected')
            TextButton(onPressed: _busy || _status == 'processing' ? null : _remove,
              child: const Text('حذف الفيديو')),
          TextButton(onPressed: _busy ? null : _refresh, child: const Text('تحديث حالة المعالجة')),
        ]),
      ),
    );
  }
}
