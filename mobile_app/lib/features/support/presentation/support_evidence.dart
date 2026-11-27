import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/platform/client_request_key.dart';
import '../../../core/platform/stage5_media_picker.dart';
import '../../../core/widgets/app_components.dart';
import '../../account/data/account_request_scope.dart';
import '../data/support_repository.dart';
import '../domain/support_models.dart';

class SupportAttachmentButton extends ConsumerWidget {
  const SupportAttachmentButton(
      {super.key,
      required this.caseId,
      required this.file,
      this.staff = false});

  final int caseId;
  final SupportAttachment file;
  final bool staff;

  @override
  Widget build(BuildContext context, WidgetRef ref) => TextButton.icon(
        onPressed: () => _open(context, ref),
        icon: const Icon(Icons.attach_file_outlined, size: 18),
        label: Text(file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      );

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final scope = ref.read(accountRequestScopeProvider);
    File? pdf;
    try {
      final bytes = Uint8List.fromList(await ref
          .read(supportRepositoryProvider)
          .file(caseId, file.id, staff: staff));
      if (!context.mounted || !scope.isCurrent) return;
      if (file.mime == 'application/pdf') {
        final temporary = await getTemporaryDirectory();
        final dir = await Directory('${temporary.path}/stage5_uploads')
            .create(recursive: true);
        pdf = await File(
                '${dir.path}/support-preview-${newClientRequestKey()}.pdf')
            .writeAsBytes(bytes);
      }
      if (!context.mounted || !scope.isCurrent) return;
      final localPdf = pdf;
      await Navigator.of(context).push<void>(MaterialPageRoute(
        builder: (_) => _EvidencePage(
            title: file.name,
            bytes: bytes,
            pdfPath: localPdf?.path,
            scope: scope),
      ));
    } catch (error) {
      if (context.mounted && scope.isCurrent) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(friendlyApiError(error))));
      }
    } finally {
      if (pdf != null) {
        try {
          await pdf.delete();
        } on FileSystemException {/* Already removed. */}
      }
    }
  }
}

class _EvidencePage extends ConsumerStatefulWidget {
  const _EvidencePage(
      {required this.title,
      required this.bytes,
      required this.scope,
      this.pdfPath});

  final String title;
  final Uint8List bytes;
  final String? pdfPath;
  final AccountRequestScope scope;

  @override
  ConsumerState<_EvidencePage> createState() => _EvidencePageState();
}

class _EvidencePageState extends ConsumerState<_EvidencePage> {
  int _page = 0;
  Future<Map<Object?, Object?>>? _preview;

  @override
  void initState() {
    super.initState();
    _preview = _render();
    _preview?.ignore();
  }

  Future<Map<Object?, Object?>>? _render() {
    final pdf = widget.pdfPath;
    return pdf == null
        ? null
        : const Stage5MediaPicker().renderSupportPdf(pdf, _page);
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(accountRequestScopeProvider);
    if (!widget.scope.isCurrent) return const SizedBox.shrink();
    return Scaffold(
      appBar: AppAppBar(title: widget.title),
      body: _preview == null
          ? _zoom(widget.bytes)
          : FutureBuilder<Map<Object?, Object?>>(
              future: _preview,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Center(child: Text('تعذّر عرض المستند.'));
                }
                final bytes = snapshot.data?['bytes'];
                if (bytes is! Uint8List) {
                  return const AppLoadingState(label: 'جارٍ عرض المستند…');
                }
                final pages = snapshot.data?['pages'] as int? ?? 1;
                return Column(children: [
                  Expanded(child: _zoom(bytes)),
                  if (pages > 1)
                    SafeArea(
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                          TextButton(
                              onPressed:
                                  _page > 0 ? () => _go(_page - 1) : null,
                              child: const Text('السابق')),
                          Text('${_page + 1} / $pages'),
                          TextButton(
                              onPressed: _page + 1 < pages
                                  ? () => _go(_page + 1)
                                  : null,
                              child: const Text('التالي')),
                        ])),
                ]);
              },
            ),
    );
  }

  void _go(int page) => setState(() {
        _page = page;
        _preview = _render();
        _preview?.ignore();
      });

  Widget _zoom(Uint8List bytes) => Center(
      child: InteractiveViewer(
          maxScale: 5, child: Image.memory(bytes, fit: BoxFit.contain)));
}
