import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../data/property_request_repository.dart';
import '../domain/property_request_models.dart';
import 'property_request_form_screen.dart';

class PropertyRequestDetailsScreen extends ConsumerStatefulWidget {
  const PropertyRequestDetailsScreen({super.key, required this.id, this.researcher = false});

  final int id;
  final bool researcher;

  @override
  ConsumerState<PropertyRequestDetailsScreen> createState() => _State();
}

class _State extends ConsumerState<PropertyRequestDetailsScreen> {
  late Future<PropertyRequestModel> future;

  @override
  void initState() {
    super.initState();
    future = _load();
  }

  Future<PropertyRequestModel> _load() {
    final repository = ref.read(propertyRequestRepositoryProvider);
    return widget.researcher
        ? repository.researcherShow(widget.id)
        : repository.show(widget.id);
  }

  void _refresh() => setState(() => future = _load());

  @override
  Widget build(BuildContext context) => Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          appBar: AppBar(title: const Text('تفاصيل طلب العقار')),
          body: FutureBuilder<PropertyRequestModel>(
            future: future,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text(friendlyApiError(snapshot.error!)));
              }
              final request = snapshot.requireData;
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _summaryCard(context, request),
                  if (widget.researcher)
                    ..._researcherActions(request)
                  else
                    ..._ownerActions(request),
                ],
              );
            },
          ),
        ),
      );

  Widget _summaryCard(BuildContext context, PropertyRequestModel request) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${request.operationLabel} • ${request.propertyTypeLabel}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(
                '${request.governorate}'
                '${request.district == null ? '' : ' • ${request.district}'}'
                '${request.area == null ? '' : ' • ${request.area}'}',
              ),
              Text(
                'الميزانية: ${request.budgetMin.toStringAsFixed(0)} - '
                '${request.budgetMax.toStringAsFixed(0)} ${request.currency}',
              ),
              if (request.requestedAreaMin != null || request.requestedAreaMax != null)
                Text(
                  'المساحة: ${request.requestedAreaMin ?? '-'} - '
                  '${request.requestedAreaMax ?? '-'} م²',
                ),
              if (request.rooms != null) Text('الغرف: ${request.rooms}'),
              if (request.additionalSpecifications != null)
                Text(request.additionalSpecifications!),
              Text('الحالة: ${request.status}'),
            ],
          ),
        ),
      );

  List<Widget> _ownerActions(PropertyRequestModel request) => [
        if (request.canEdit)
          OutlinedButton(
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PropertyRequestFormScreen(request: request),
                ),
              );
              _refresh();
            },
            child: const Text('تعديل الطلب'),
          ),
        if (request.canClose)
          FilledButton.tonal(
            onPressed: () async {
              try {
                await ref.read(propertyRequestRepositoryProvider).close(request.id);
                ref.invalidate(myPropertyRequestsProvider);
                _refresh();
              } catch (error) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(friendlyApiError(error))),
                  );
                }
              }
            },
            child: const Text('إغلاق الطلب'),
          ),
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('العقارات المقترحة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        ),
        ...request.suggestions.map(
          (suggestion) => Card(
            child: ListTile(
              title: Text(suggestion.property?.title ?? 'عقار مقترح'),
              subtitle: Text(suggestion.note ?? 'اقترحه ${suggestion.suggestedByName}'),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => context.push('/properties/${suggestion.propertyId}'),
            ),
          ),
        ),
      ];

  List<Widget> _researcherActions(PropertyRequestModel request) => [
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 12),
          child: Text('عقاراتي المطابقة والمنشورة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        ),
        ...request.eligibleProperties.map(
          (property) => Card(
            child: ListTile(
              title: Text(property.title),
              subtitle: Text('${property.price.toStringAsFixed(0)} ${property.currency}'),
              trailing: FilledButton(
                onPressed: () => _suggest(request.id, property),
                child: const Text('اقتراح'),
              ),
            ),
          ),
        ),
      ];

  Future<void> _suggest(int requestId, SuggestableProperty property) async {
    try {
      await ref.read(propertyRequestRepositoryProvider).suggest(requestId, property.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إرسال الاقتراح وإشعار الباحث.')),
        );
        context.push('/properties/${property.id}');
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyApiError(error))),
        );
      }
    }
  }
}
