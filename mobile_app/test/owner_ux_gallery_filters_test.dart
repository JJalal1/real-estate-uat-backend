import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/widgets/app_components.dart';
import 'package:real_estate_mobile/core/widgets/ebroker_property_card.dart';
import 'package:real_estate_mobile/features/discovery/domain/smart_search_filters.dart';
import 'package:real_estate_mobile/features/discovery/presentation/smart_search_filter_editor.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';
import 'package:real_estate_mobile/features/properties/presentation/property_fullscreen_gallery.dart';
import 'support/owner_ux_fixtures.dart';

const _images = [
  PropertyImageItem(id: 801, url: 'https://real-estate-uat-api-frankfurt.onrender.com/api/property-media/801?v=synthetic-only', isPrimary: true, sortOrder: 0),
  PropertyImageItem(id: 802, url: 'https://real-estate-uat-api-frankfurt.onrender.com/api/property-media/802?v=synthetic-only', isPrimary: false, sortOrder: 1),
];
const _gallery = PropertyFullscreenGallery(images: _images, initialIndex: 0);
Finder get _viewer => find.byType(InteractiveViewer).hitTestable().first;
Matrix4 _matrix(WidgetTester tester) => tester.widget<InteractiveViewer>(_viewer).transformationController!.value;
Future<void> _twice(WidgetTester tester, Offset point) async {
  await tester.tapAt(point); await tester.pump(const Duration(milliseconds: 80));
  await tester.tapAt(point); await tester.pump(); await tester.pump(const Duration(milliseconds: 280));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(loadUxFixtures);
  testWidgets('double tap anchors zoom at the touch point, resets, and keeps controls fixed', (tester) async {
    final scope = uxContainer();
    await pumpUx(tester, scope, _gallery);
    final bounds = tester.getRect(_viewer), tap = bounds.topLeft + const Offset(110, 290);
    final close = tester.getRect(find.byKey(const ValueKey('gallery-close')));
    final counter = tester.getRect(find.byKey(const ValueKey('gallery-counter')));
    expect(bounds, const Rect.fromLTWH(0, 0, 412, 820));
    await _twice(tester, tap);
    final zoom = _matrix(tester);
    expect(zoom.getMaxScaleOnAxis(), closeTo(2.5, .01));
    expect(zoom.storage[12], closeTo(110 * -1.5, 1));
    expect(zoom.storage[13], closeTo(290 * -1.5, 1));
    expect(tester.getRect(find.byKey(const ValueKey('gallery-close'))), close);
    expect(tester.getRect(find.byKey(const ValueKey('gallery-counter'))), counter);
    await tester.dragFrom(tap, const Offset(120, 0)); await uxFrames(tester);
    expect(find.text('1/2'), findsOneWidget); // Zoomed pan cannot page.
    await _twice(tester, tap);
    expect(_matrix(tester).getMaxScaleOnAxis(), closeTo(1, .01));
    await tester.dragFrom(const Offset(80, 360), const Offset(230, 0)); await uxFrames(tester);
    expect(find.text('2/2'), findsOneWidget);
    expect(_matrix(tester).getMaxScaleOnAxis(), closeTo(1, .01));
    await tester.dragFrom(const Offset(320, 360), const Offset(-230, 0)); await uxFrames(tester);
    expect(find.text('1/2'), findsOneWidget);
    expect(_matrix(tester).getMaxScaleOnAxis(), closeTo(1, .01));
    expect(tester.takeException(), isNull); await closeUx(tester);
  });

  testWidgets('a real two-pointer pinch zooms without changing the page', (tester) async {
    await pumpUx(tester, uxContainer(), _gallery);
    final first = await tester.startGesture(const Offset(160, 400), pointer: 1);
    final second = await tester.startGesture(const Offset(250, 400), pointer: 2);
    await tester.pump();
    await first.moveTo(const Offset(110, 400)); await second.moveTo(const Offset(300, 400)); await tester.pump();
    await first.moveTo(const Offset(60, 400)); await second.moveTo(const Offset(350, 400)); await tester.pump();
    await first.up(); await second.up(); await uxFrames(tester);
    expect(_matrix(tester).getMaxScaleOnAxis(), greaterThan(1.2));
    expect(find.text('1/2'), findsOneWidget);
    expect(tester.takeException(), isNull); await closeUx(tester);
  });

  testWidgets('guidance ignores touches, expires and is shown once per actor session', (tester) async {
    final scope = uxContainer();
    await pumpUx(tester, scope, _gallery);
    final hints = find.ancestor(of: find.byKey(const ValueKey('gallery-guidance')), matching: find.byType(AnimatedOpacity));
    expect(tester.widget<AnimatedOpacity>(hints).opacity, 1);
    expect(tester.widget<IgnorePointer>(find.ancestor(of: hints, matching: find.byType(IgnorePointer)).first).ignoring, isTrue);
    await tester.pump(const Duration(milliseconds: 4300)); await tester.pump(const Duration(milliseconds: 250));
    expect(tester.widget<AnimatedOpacity>(hints).opacity, 0);
    await closeUx(tester); await pumpUx(tester, scope, _gallery);
    expect(tester.widget<AnimatedOpacity>(hints).opacity, 0);
    await closeUx(tester);
  });

  testWidgets('private gallery hides the old account immediately after switching', (tester) async {
    final auth = UxAuth(uxUser(type: 'broker'));
    await pumpUx(tester, uxContainer(auth: auth), const PropertyFullscreenGallery(images: _images, initialIndex: 0, privateImages: true));
    expect(find.byType(InteractiveViewer), findsWidgets);
    auth.change(uxUser(id: 2)); await uxFrames(tester);
    expect(find.byType(InteractiveViewer), findsNothing);
    expect(find.text('تغيّر الحساب'), findsOneWidget);
    await closeUx(tester);
  });

  for (final dark in [false, true]) {
    for (final scale in [1.0, 2.4]) {
      testWidgets('small RTL gallery and long card price theme $dark scale $scale', (tester) async {
        final scope = uxContainer(), boundary = GlobalKey();
        await pumpUx(tester, scope, _gallery, size: const Size(320, 568), scale: scale, dark: dark, boundary: boundary);
        expect(tester.getRect(_viewer), const Rect.fromLTWH(0, 0, 320, 568));
        await uxPreview(tester, boundary, 'gallery-${dark ? 'dark' : 'light'}-$scale');
        expect(find.byWidgetPredicate((widget) => widget is RawImage && widget.image != null), findsWidgets);
        expect(tester.takeException(), isNull); await closeUx(tester);
        await pumpUx(tester, scope, Scaffold(body: SingleChildScrollView(child: EbrokerPropertyHorizontalCard(
          title: 'منزل للبيع في إب', price: '999999999999', currency: 'YER', imageFirst: true,
          imageUrl: _images.first.url, onTap: () {}))), size: const Size(320, 568), scale: scale, dark: dark, boundary: boundary);
        final price = tester.widget<AppPropertyPrice>(find.byType(AppPropertyPrice));
        expect(price.compact, isTrue); expect(price.price, '999999999999');
        final text = tester.widget<Text>(find.descendant(of: find.byType(AppPropertyPrice), matching: find.byType(Text)));
        final amount = (text.textSpan! as TextSpan).children!.first as TextSpan;
        expect(amount.style!.fontSize! / 18, closeTo(.75, .001));
        expect(text.maxLines, 1); expect(text.overflow, TextOverflow.ellipsis);
        final badge = tester.getRect(find.byKey(const ValueKey('property-photo-price')));
        expect(badge.left, greaterThanOrEqualTo(0)); expect(badge.right, lessThanOrEqualTo(320));
        await uxPreview(tester, boundary, 'price-${dark ? 'dark' : 'light'}-$scale');
        expect(find.byWidgetPredicate((widget) => widget is RawImage && widget.image != null), findsWidgets);
        expect(tester.takeException(), isNull); await closeUx(tester);
      });
    }
  }

  testWidgets('room chips preserve a saved minimum, toggle clear, and submit scalar API filters', (tester) async {
    SmartSearchFilters? result;
    await pumpUx(tester, uxContainer(), Builder(builder: (context) => Scaffold(body: TextButton(
      onPressed: () async { result = await showModalBottomSheet<SmartSearchFilters>(context: context, isScrollControlled: true,
        builder: (_) => SmartSearchFilterEditor(initial: SmartSearchFilters.fromMap({'type': 'house', 'purpose': 'sale',
          'min_bedrooms': 8, 'min_bathrooms': 2, 'min_price': 100, 'max_price': 900, 'min_area_m2': 50, 'max_area_m2': 500}))); },
      child: const Text('افتح الشروط')))));
    await tester.tap(find.text('افتح الشروط')); await uxFrames(tester);
    final saved = find.byKey(const ValueKey('filter-min_bedrooms-8'));
    await tester.ensureVisible(saved); expect(tester.widget<ChoiceChip>(saved).selected, isTrue);
    final six = find.byKey(const ValueKey('filter-min_bedrooms-6'));
    await tester.ensureVisible(six); await tester.tap(six); await tester.pump();
    expect(tester.widget<ChoiceChip>(six).selected, isTrue);
    await tester.tap(six); await tester.pump();
    expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('filter-min_bedrooms-all'))).selected, isTrue);
    await tester.tap(six); await tester.pump();
    final five = find.byKey(const ValueKey('filter-min_bathrooms-5'));
    await tester.ensureVisible(five); await tester.tap(five); await tester.pump();
    final apply = find.text('تطبيق الشروط'); await tester.ensureVisible(apply); await tester.tap(apply); await uxFrames(tester);
    expect(result!.apiFilters, containsPair('min_bedrooms', 6));
    expect(result!.apiFilters, containsPair('min_bathrooms', 5));
    expect(result!.apiFilters, containsPair('min_price', 100)); expect(result!.apiFilters, containsPair('max_price', 900));
    expect(result!.apiFilters, containsPair('min_area_m2', 50)); expect(result!.apiFilters, containsPair('max_area_m2', 500));
    expect(result!.apiFilters.values.any((value) => value is List), isFalse);
    expect(tester.takeException(), isNull); await closeUx(tester);
  });

  testWidgets('type and purpose chips clear and restore incompatible fields through the existing schema', (tester) async {
    final boundary = GlobalKey();
    await pumpUx(tester, uxContainer(), Scaffold(body: SmartSearchFilterEditor(initial: SmartSearchFilters.fromMap({'type': 'house'}))),
      size: const Size(320, 568), scale: 2.4, dark: true, boundary: boundary);
    final house = find.byKey(const ValueKey('filter-type-house'));
    await tester.ensureVisible(house); await tester.tap(house); await tester.pump();
    expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('filter-type-all'))).selected, isTrue);
    final land = find.byKey(const ValueKey('filter-type-land'));
    await tester.ensureVisible(land); await tester.tap(land); await tester.pump();
    expect(find.byKey(const ValueKey('filter-min_bedrooms')), findsNothing);
    final rent = find.byKey(const ValueKey('filter-purpose-rent'));
    await tester.ensureVisible(rent); await tester.tap(rent); await tester.pump();
    expect(tester.widget<ChoiceChip>(rent).selected, isTrue);
    await tester.tap(rent); await tester.pump();
    expect(tester.widget<ChoiceChip>(find.byKey(const ValueKey('filter-purpose-all'))).selected, isTrue);
    final currency = find.byKey(const ValueKey('filter-currency'));
    await tester.ensureVisible(currency); await tester.pumpAndSettle();
    final label = find.descendant(of: currency, matching: find.text('ريال يمني للميزانية')).first;
    final fieldBounds = tester.getRect(currency), labelBounds = tester.getRect(label);
    expect(labelBounds.top, greaterThanOrEqualTo(fieldBounds.top));
    expect(labelBounds.bottom, lessThanOrEqualTo(fieldBounds.bottom));
    await uxPreview(tester, boundary, 'filters-dark-2.4');
    expect(tester.takeException(), isNull); await closeUx(tester);
  });
}
