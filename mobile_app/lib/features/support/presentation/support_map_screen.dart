import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../../core/network/api_error_message.dart';
import '../../../core/widgets/app_components.dart';
import '../../discovery/data/marketplace_repository.dart';
import '../../discovery/domain/smart_search_filters.dart';
import '../../map/presentation/map_screen.dart';
import '../data/support_workspace_repository.dart';

final _supportMapCodesProvider = FutureProvider.autoDispose.family<Set<String>, bool>(
  (ref, actingAsAgent) async {
    final repository = ref.watch(supportWorkspaceRepositoryProvider);
    final dashboard = await (actingAsAgent ? repository.agentDashboard() : repository.dashboard());
    return dashboard.governorateCodes;
  },
);

class SupportMapScreen extends ConsumerStatefulWidget {
  const SupportMapScreen({this.actingAsAgent = false, super.key});
  final bool actingAsAgent;

  @override
  ConsumerState<SupportMapScreen> createState() => _SupportMapScreenState();
}

class _SupportMapScreenState extends ConsumerState<SupportMapScreen> {
  String? _selectedCode;

  @override
  Widget build(BuildContext context) {
    final scopeProvider = _supportMapCodesProvider(widget.actingAsAgent);
    final scope = ref.watch(scopeProvider);
    final locations = ref.watch(homeLocationsProvider);
    final error = scope.asError?.error ?? locations.asError?.error;
    final codes = scope.asData?.value;
    final locationsData = locations.asData?.value;
    final allowed = locationsData
        ?.where((row) => codes?.contains(row.governorateCode) ?? false)
        .toList() ?? const <HomeLocation>[];
    final selected = allowed.isEmpty
        ? null
        : allowed.firstWhere(
            (row) => row.governorateCode == _selectedCode,
            orElse: () => allowed.first,
          );

    return Scaffold(
      appBar: AppBar(title: const Text('خريطة الدعم')),
      body: error != null
          ? AppErrorState(
              message: friendlyApiError(error),
              onRetry: () {
                ref.invalidate(scopeProvider);
                ref.invalidate(homeLocationsProvider);
              },
            )
          : codes == null || locationsData == null
              ? const AppLoadingState(label: 'جارٍ تحميل نطاق فريقك…')
              : selected == null
                  ? const Center(child: Text('لم تُحدَّد محافظة لفريقك بعد.'))
                  : Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: DropdownButtonFormField<String>(
                            value: selected.governorateCode,
                            decoration: const InputDecoration(labelText: 'محافظة الفريق'),
                            isExpanded: true,
                            items: [
                              for (final row in allowed)
                                DropdownMenuItem(value: row.governorateCode, child: Text(row.label)),
                            ],
                            onChanged: allowed.length == 1
                                ? null
                                : (code) => setState(() => _selectedCode = code),
                          ),
                        ),
                        Expanded(
                          child: MapScreen(
                            key: ValueKey(selected.governorateCode),
                            lockedGovernorateCode: selected.governorateCode,
                            cameraCenterHint: LatLng(selected.latitude, selected.longitude),
                            initialFilters: SmartSearchFilters.fromMap(selected.provinceSearchContext),
                          ),
                        ),
                      ],
                    ),
    );
  }
}
