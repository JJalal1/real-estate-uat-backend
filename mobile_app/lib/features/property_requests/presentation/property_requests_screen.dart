import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_error_message.dart';
import '../data/property_request_repository.dart';
import '../domain/property_request_models.dart';

class PropertyRequestsScreen extends ConsumerWidget {
  const PropertyRequestsScreen({super.key, this.researcher = false});

  final bool researcher;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final provider = researcher ? researcherRequestsProvider : myPropertyRequestsProvider;
    final value = ref.watch(provider);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: Text(researcher ? 'طلبات الباحثين' : 'طلبات العقار')),
        floatingActionButton: researcher
            ? null
            : FloatingActionButton.extended(
                onPressed: () => context.push('/property-requests/new'),
                icon: const Icon(Icons.add),
                label: const Text('طلب جديد'),
              ),
        body: value.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(child: Text(friendlyApiError(error))),
          data: (rows) => RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(provider);
              await ref.read(provider.future);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: rows.isEmpty
                  ? const [
                      Card(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Text('لا توجد طلبات متاحة.'),
                        ),
                      ),
                    ]
                  : rows
                      .map((request) => _RequestCard(
                            request: request,
                            researcher: researcher,
                          ))
                      .toList(),
            ),
          ),
        ),
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request, required this.researcher});

  final PropertyRequestModel request;
  final bool researcher;

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          title: Text(
            '${request.operationType == 'sale' ? 'شراء' : 'إيجار'} • ${request.propertyType}',
          ),
          subtitle: Text(
            '${request.governorate}${request.district == null ? '' : ' • ${request.district}'}\n'
            '${request.budgetMin.toStringAsFixed(0)} - '
            '${request.budgetMax.toStringAsFixed(0)} ${request.currency} • ${request.status}',
          ),
          isThreeLine: true,
          trailing: const Icon(Icons.chevron_left),
          onTap: () => context.push(
            researcher
                ? '/researcher-requests/${request.id}'
                : '/property-requests/${request.id}',
          ),
        ),
      );
}
