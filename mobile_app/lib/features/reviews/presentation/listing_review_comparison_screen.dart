import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_components.dart';
import '../../properties/domain/property_field_options.dart';
import '../domain/listing_duplicate_candidate.dart';
import '../domain/listing_review_models.dart';
import 'listing_duplicate_notice.dart';
import 'review_protected_photo.dart';

enum ListingComparisonAction { link, reject, openPrevious }

class ListingReviewComparisonScreen extends StatelessWidget {
  const ListingReviewComparisonScreen({
    super.key,
    required this.listing,
    required this.candidate,
    required this.canDecide,
    required this.onPhoto,
  });

  final ReviewListingDetail listing;
  final ListingDuplicateCandidate candidate;
  final bool canDecide;
  final ValueChanged<ReviewMediaItem> onPhoto;

  @override
  Widget build(BuildContext context) {
    final currentPhoto = listing.images.firstOrNull;
    final imageUrl = candidate.imageUrl;
    final imageId = candidate.mainImageId;
    final candidatePhoto = imageUrl == null || imageId == null
        ? null
        : ReviewMediaItem(id: imageId, url: imageUrl);
    final colors = Theme.of(context).colorScheme;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppAppBar(
          title: 'مقارنة الإعلانين',
          actions: [
            if (canDecide && candidate.propertyAssetId > 0)
              PopupMenuButton<ListingComparisonAction>(
                tooltip: 'المزيد',
                onSelected: (action) => Navigator.pop(context, action),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: ListingComparisonAction.link,
                    child: Text('ربط الإعلان بهوية العقار المشابه'),
                  ),
                ],
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            AppInlineMessage(
              title: candidate.severityLabel,
              message: 'المسافة بين الإعلانين ${arabicDigits('${candidate.distanceM}')} مترًا.',
              tone: AppStatusTone.warning,
            ),
            if (candidate.detection case final detection?) ...[
              const SizedBox(height: AppSpacing.s8),
              ListingDuplicateNotice(detection: detection),
            ],
            const SizedBox(height: AppSpacing.s12),
            AppSurface(
              padding: EdgeInsets.zero,
              child: Table(
                border: TableBorder(
                  horizontalInside: BorderSide(color: colors.outlineVariant),
                  verticalInside: BorderSide(color: colors.outlineVariant),
                ),
                children: [
                  TableRow(children: [
                    _fact(context, 'الإعلان الحالي · ${arabicDigits('${listing.id}')}', listing.title),
                    _fact(context, 'الإعلان المشابه · ${arabicDigits('${candidate.listingId}')}', candidate.title),
                  ]),
                  TableRow(children: [
                    _photo(currentPhoto),
                    _photo(candidatePhoto),
                  ]),
                  TableRow(children: [
                    _fact(context, 'العنوان', listing.address),
                    _fact(context, 'العنوان', candidate.address),
                  ]),
                  TableRow(children: [
                    _fact(context, 'المساحة', _area(listing.areaValue, listing.areaM2, listing.areaUnit)),
                    _fact(context, 'المساحة', _area(candidate.areaValue, candidate.areaM2, candidate.areaUnit)),
                  ]),
                  TableRow(children: [
                    _fact(context, 'السعر', _price(listing.price, listing.currency)),
                    _fact(context, 'السعر', _price(candidate.price, candidate.currency)),
                  ]),
                ],
              ),
            ),
            if (candidate.signalLabels.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.s12),
              const AppSectionHeader(title: 'أسباب الاشتباه'),
              const SizedBox(height: AppSpacing.s8),
              Wrap(
                spacing: AppSpacing.s4,
                runSpacing: AppSpacing.s4,
                children: [
                  for (final signal in candidate.signalLabels)
                    AppStatusBadge(label: signal, tone: AppStatusTone.neutral),
                ],
              ),
            ],
            const SizedBox(height: AppSpacing.s12),
            if (candidate.canRejectAsDuplicate)
              Wrap(
                spacing: AppSpacing.s8,
                runSpacing: AppSpacing.s8,
                children: [
                  AppButton(
                    label: 'عرض الإعلان السابق',
                    style: AppButtonStyle.outlined,
                    onPressed: () => Navigator.pop(context, ListingComparisonAction.openPrevious),
                  ),
                  if (canDecide)
                    AppButton(
                      label: 'رفض الإعلان الجديد كمكرر',
                      style: AppButtonStyle.tonal,
                      onPressed: () => Navigator.pop(context, ListingComparisonAction.reject),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _photo(ReviewMediaItem? photo) => Padding(
    padding: const EdgeInsets.all(8),
    child: photo == null
        ? const SizedBox(height: 142, child: Center(child: Text('الصورة غير متاحة')))
        : ReviewPhotoPreview(photo: photo, height: 142, onOpen: () => onPhoto(photo)),
  );

  Widget _fact(BuildContext context, String label, String? value) => Padding(
    padding: const EdgeInsets.all(10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelMedium),
        const SizedBox(height: AppSpacing.s4),
        Text(value == null || value.isEmpty ? '—' : value),
      ],
    ),
  );

  String? _area(double? value, int? squareMetres, String? unit) {
    if (value != null && unit != null) {
      return '${formatPropertyAreaValue(value)} ${propertyAreaUnitLabel(unit)}';
    }
    return squareMetres == null ? null : '${formatPropertyAreaValue(squareMetres.toDouble())} م²';
  }

  String? _price(double? price, String? currency) {
    if (price == null) return null;
    return currency == null ? formatMoneyAmount(price) : moneyLabel(price, currency);
  }
}
