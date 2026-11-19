import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_components.dart';
import '../../discovery/data/discovery_suggestions.dart';
import '../../discovery/data/marketplace_repository.dart';

Future<MapAddressMatch?> showMapAddressSearch(
  BuildContext context, {
  required bool useGoogle,
}) =>
    AppBottomSheet.show<MapAddressMatch>(
      context,
      builder: (_) => _MapAddressSearchSheet(useGoogle: useGoogle),
    );

class _MapAddressSearchSheet extends ConsumerStatefulWidget {
  const _MapAddressSearchSheet({required this.useGoogle});
  final bool useGoogle;

  @override
  ConsumerState<_MapAddressSearchSheet> createState() =>
      _MapAddressSearchSheetState();
}

class _MapAddressSearchSheetState
    extends ConsumerState<_MapAddressSearchSheet> {
  final _input = TextEditingController();
  CancelToken? _request;
  List<MapAddressMatch> _addressMatches = const [];
  bool _searched = false;
  bool _addressSearchUnavailable = false;

  @override
  void dispose() {
    _request?.cancel();
    _input.dispose();
    super.dispose();
  }

  void _edit() {
    _request?.cancel();
    setState(() {
      _request = null;
      _searched = false;
      _addressMatches = const [];
      _addressSearchUnavailable = false;
    });
  }

  Future<void> _search(List<HomeLocation> places) async {
    final address = _input.text.trim();
    if (address.length < 2 || _request != null) return;
    FocusScope.of(context).unfocus();
    if (places.any((place) =>
        normalizeDiscoveryText(place.label) ==
        normalizeDiscoveryText(address))) {
      setState(() => _searched = true);
      return;
    }
    final request = CancelToken();
    setState(() => _request = request);
    List<MapAddressMatch>? matches;
    try {
      matches = await ref
          .read(discoverySuggestionsRepositoryProvider)
          .areasOnMap(address, request);
    } catch (_) {
      // The built-in governorate choices can still be used.
    }
    if (!mounted || !identical(_request, request)) return;
    if (widget.useGoogle && (matches == null || matches.isEmpty)) {
      try {
        matches = await ref
            .read(marketplaceRepositoryProvider)
            .findMapAddress(address, request);
      } catch (_) {
        matches = null;
      }
    }
    if (!mounted || !identical(_request, request)) return;
    setState(() {
      _request = null;
      _searched = true;
      _addressSearchUnavailable = matches == null;
      _addressMatches = matches ?? const [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final places = ref.watch(homeLocationsProvider);
    final catalog = places.asData?.value ?? const <HomeLocation>[];
    final query = normalizeDiscoveryText(_input.text);
    final governorates = catalog.where((row) {
      final name = normalizeDiscoveryText(row.label);
      return query.isEmpty || name.contains(query);
    });
    void pick(MapAddressMatch match) => Navigator.of(context).pop(match);
    final textTheme = Theme.of(context).textTheme;

    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
            18, 18, 18, 18 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('انتقل إلى مكان على الخريطة', style: textTheme.titleLarge),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('map-address-input'),
                controller: _input,
                maxLength: 120,
                textInputAction: TextInputAction.search,
                onChanged: (_) => _edit(),
                onSubmitted: (_) => _search(catalog),
                decoration: InputDecoration(
                  labelText: widget.useGoogle
                      ? 'اسم المحافظة أو الحي أو العنوان'
                      : 'اسم المحافظة أو الحي',
                  prefixIcon: const Icon(Icons.search),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 8),
              FilledButton(
                key: const ValueKey('map-address-submit'),
                onPressed: query.length < 2 || _request != null
                    ? null
                    : () => _search(catalog),
                child: const Text('بحث'),
              ),
              if (_request != null || places.isLoading)
                const LinearProgressIndicator(),
              if (places.hasError && query.isEmpty)
                const Text('تعذّر تحميل المحافظات.'),
              for (final place in governorates)
                ListTile(
                  leading: const Icon(Icons.location_on_outlined),
                  title: Text(place.label),
                  onTap: () => pick(MapAddressMatch(
                    label: place.label,
                    latitude: place.latitude,
                    longitude: place.longitude,
                    zoom: 9,
                  )),
                ),
              if (_addressMatches.isNotEmpty) ...[
                if (_addressMatches.any((match) => match.google))
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('Google Maps',
                        textDirection: TextDirection.ltr,
                        textAlign: TextAlign.start,
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w500)),
                  ),
                for (final match in _addressMatches)
                  ListTile(
                    leading: const Icon(Icons.location_on_outlined),
                    title: Text(match.label),
                    subtitle:
                        match.partial ? const Text('مطابقة تقريبية') : null,
                    onTap: () => pick(match),
                  ),
              ],
              if (_addressSearchUnavailable)
                const Text(
                    'تعذّر البحث عن العناوين الآن. يمكنك تحديد المكان على الخريطة.'),
              if (!_addressSearchUnavailable &&
                  governorates.isEmpty &&
                  _addressMatches.isEmpty &&
                  _searched)
                const Text('لم نجد مكانًا بهذا الاسم.'),
            ]),
      ),
    );
  }
}
