import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../bookings/presentation/booking_request_sheet.dart';
import '../data/development_repository.dart';
import '../domain/development_models.dart';

class DevelopmentDetailsScreen extends ConsumerWidget {
  const DevelopmentDetailsScreen({super.key, required this.developmentId});
  final int developmentId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('تفاصيل المشروع')),
        body: FutureBuilder<DevelopmentDetails>(
          future: ref
              .read(developmentRepositoryProvider)
              .publicProject(developmentId),
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError || snapshot.data == null) {
              return const Center(
                  child: Text('تعذر فتح المشروع أو أنه غير منشور.'));
            }
            final details = snapshot.data!;
            final p = details.summary;
            return ListView(padding: const EdgeInsets.all(16), children: [
              Text(p.name,
                  style: Theme.of(context)
                      .textTheme
                      .headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 6),
              Text(p.developer?.name ?? '',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800)),
              if (p.address != null) ...[
                const SizedBox(height: 10),
                ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.location_on_outlined),
                    title: Text(p.address!))
              ],
              if (p.description != null) ...[
                const SizedBox(height: 12),
                Text('عن المشروع',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 6),
                Text(p.description!, style: const TextStyle(height: 1.6))
              ],
              const SizedBox(height: 18),
              Text('الوحدات',
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              if (details.units.isEmpty)
                const Card(
                    child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('لا توجد وحدات معروضة حالياً.')))
              else
                ...details.units.map((unit) => _UnitCard(
                    unit: unit,
                    onRequest: unit.status == 'available'
                        ? () => BookingRequestSheet.showForDevelopmentUnit(
                            context,
                            unitId: unit.id,
                            title: '${p.name} - ${unit.title}')
                        : null)),
            ]);
          },
        ),
      ),
    );
  }
}

class _UnitCard extends StatelessWidget {
  const _UnitCard({required this.unit, this.onRequest});
  final DevelopmentUnitItem unit;
  final VoidCallback? onRequest;
  @override
  Widget build(BuildContext context) {
    final price = unit.price == null
        ? 'السعر عند الطلب'
        : '${unit.price!.toStringAsFixed(0)} ${unit.currency}';
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(14),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(
                    child: Text('${unit.title} (${unit.code})',
                        style: const TextStyle(fontWeight: FontWeight.w900))),
                Chip(label: Text(_status(unit.status)))
              ]),
              const SizedBox(height: 6),
              Text('${unit.areaM2.toStringAsFixed(1)} م² • $price'),
              if (unit.bedrooms != null || unit.bathrooms != null)
                Text(
                    'غرف: ${unit.bedrooms ?? '-'} • حمامات: ${unit.bathrooms?.toStringAsFixed(1) ?? '-'}'),
              if (unit.description != null) ...[
                const SizedBox(height: 6),
                Text(unit.description!)
              ],
              if (onRequest != null) ...[
                const SizedBox(height: 10),
                FilledButton.tonalIcon(
                    onPressed: onRequest,
                    icon: const Icon(Icons.event_available_outlined),
                    label: const Text('طلب معاينة هذه الوحدة'))
              ],
            ])));
  }

  static String _status(String value) => switch (value) {
        'reserved' => 'محجوزة',
        'sold' => 'مباعة',
        _ => 'متاحة'
      };
}
