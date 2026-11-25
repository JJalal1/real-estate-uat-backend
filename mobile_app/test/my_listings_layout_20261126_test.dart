import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:real_estate_mobile/core/theme/app_theme.dart';
import 'package:real_estate_mobile/features/properties/domain/my_listings_page.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';
import 'package:real_estate_mobile/features/properties/presentation/my_listings_screen.dart';

PropertyDetails _listing(
  int id,
  String title, {
  String purpose = 'sale',
  String status = 'published',
  String review = 'approved',
  String availability = 'available',
  String? reason,
  bool canEdit = true,
}) =>
    PropertyDetails(
      id: id,
      title: title,
      purpose: purpose,
      type: 'building',
      price: 5000000,
      currency: 'YER',
      latitude: 14.5,
      longitude: 44.4,
      address: 'ذمار',
      areaValue: 100,
      areaUnit: 'sqm',
      hasParking: true,
      floorsCount: 4,
      buildingFacade: 'east',
      images: const [],
      status: status,
      reviewStatus: review,
      availabilityStatus: availability,
      lastReviewReason: reason,
      canEdit: canEdit,
      canSubmit: review == 'returned_for_correction',
      proofDocumentCount: 2,
    );

Finder _filter(String name) => find.byKey(ValueKey('my-listings-filter-$name'));
Finder _card(int id) => find.byKey(ValueKey('owner-listing-$id'));
final _drafts = find.byKey(const ValueKey('my-saved-listing-drafts'));

Future<void> _open(
  WidgetTester tester,
  List<PropertyDetails> listings, {
  bool corrections = false,
  double textScale = 1,
}) async {
  tester.view.physicalSize = const Size(390, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final router = GoRouter(
    initialLocation: '/my-listings',
    routes: [
      GoRoute(
        path: '/my-listings',
        builder: (_, __) =>
            MyListingsScreen(initiallyShowCorrections: corrections),
      ),
      GoRoute(
        path: '/add-property',
        builder: (_, state) => Scaffold(
          body: Text('مسار المسودات ${state.uri.queryParameters['drafts']}'),
        ),
      ),
      GoRoute(
        path: '/properties/:id',
        builder: (_, state) => Scaffold(
          body: Text('تفاصيل العقار ${state.pathParameters['id']}'),
        ),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        myListingsPagesProvider.overrideWith(
          (_) => MyListingsPagesController(
            load: (_) async => MyListingsPage(
              items: listings,
              currentPage: 1,
              lastPage: 1,
              total: listings.length,
            ),
            signedIn: true,
            isCurrent: () => true,
            onSessionChange: () {},
          ),
        ),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light,
        routerConfig: router,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('one RTL filter row keeps closed owner history and draft route',
      (tester) async {
    await _open(tester, [
      _listing(1, 'عقار مباع', availability: 'sold'),
      _listing(2, 'عقار مؤجر', purpose: 'rent', availability: 'rented'),
      _listing(3, 'مسودة سابقة', status: 'draft', review: 'draft'),
      _listing(4, 'عقار منشور'),
      _listing(5, 'إعلان ينتظر القرار',
          status: 'pending', review: 'submitted', canEdit: false),
    ]);

    final chips = [
      _filter('all'),
      _filter('published'),
      _filter('review'),
      _filter('rejected'),
      _drafts,
    ].map(tester.getCenter).toList();
    expect(chips.map((point) => point.dy).toSet(), hasLength(1));
    expect(
        chips.map((point) => point.dx),
        orderedEquals(
          chips.map((point) => point.dx).toList()
            ..sort((a, b) => b.compareTo(a)),
        ));
    expect(tester.getRect(_drafts).left, greaterThanOrEqualTo(0));
    expect(
        find.descendant(
            of: _drafts, matching: find.byIcon(Icons.drafts_outlined)),
        findsOneWidget);
    expect(find.text('ملخص إعلاناتك'), findsNothing);
    expect(find.byTooltip('تحديث التوفر الجماعي'), findsNothing);
    expect(_card(3), findsNothing);
    expect(find.descendant(of: _card(1), matching: find.text('تم البيع')),
        findsOneWidget);
    expect(find.descendant(of: _card(2), matching: find.text('تم التأجير')),
        findsOneWidget);

    await tester.tap(_filter('published'));
    await tester.pumpAndSettle();
    expect(_card(4), findsOneWidget);
    expect(_card(1), findsNothing);
    expect(_card(2), findsNothing);
    expect(_card(5), findsNothing);
    await tester.tap(_filter('review'));
    await tester.pumpAndSettle();
    expect(_card(5), findsOneWidget);
    expect(find.text('بانتظار فريق المراجعة'), findsNothing);
    expect(find.text('2 إثبات'), findsNothing);
    expect(find.text('عرض'), findsNothing);
    await tester.tap(find.text('إعلان ينتظر القرار'));
    await tester.pumpAndSettle();
    expect(find.text('تفاصيل العقار 5'), findsOneWidget);

    final router = GoRouter.of(tester.element(find.text('تفاصيل العقار 5')));
    router.pop();
    await tester.pumpAndSettle();
    await tester.tap(_drafts);
    await tester.pumpAndSettle();
    expect(find.text('مسار المسودات 1'), findsOneWidget);
  });

  testWidgets(
      'facts stay by the photo and rejection respects actual edit rights',
      (tester) async {
    final editable = _listing(1, 'إعلان سابق مرفوض',
        status: 'rejected',
        review: 'legacy_rejected',
        reason: 'العنوان يحتاج إلى توضيح');
    final locked = _listing(2, 'إعلان مكرر',
        status: 'rejected',
        review: 'rejected_duplicate',
        reason: 'يتطابق مع إعلان سابق',
        canEdit: false);
    await _open(tester, [editable, locked]);
    await tester.tap(_filter('rejected'));
    await tester.pumpAndSettle();

    Finder within(Finder card, String key) => find.descendant(
          of: card,
          matching: find.byKey(ValueKey(key)),
        );
    final photo = tester.getRect(within(_card(1), 'my-listing-photo'));
    final facts = tester.getRect(within(_card(1), 'my-listing-facts'));
    expect(facts.right, lessThan(photo.left));
    expect(facts.top, lessThan(photo.bottom));
    expect(find.descendant(of: _card(1), matching: find.text('٤ أدوار')),
        findsOneWidget);
    expect(find.descendant(of: _card(1), matching: find.text('واجهة شرقية')),
        findsOneWidget);
    expect(find.text('مصعد'), findsNothing);

    final editableRow = within(_card(1), 'listing-review-row');
    final reason = find.descendant(
        of: editableRow,
        matching: find.text('سبب الرفض: العنوان يحتاج إلى توضيح'));
    final edit =
        find.descendant(of: editableRow, matching: find.text('تعديل الإعلان'));
    expect(tester.getCenter(reason).dy, closeTo(tester.getCenter(edit).dy, 2));
    expect(
        find.descendant(
            of: _card(2),
            matching: find.text('سبب الرفض: يتطابق مع إعلان سابق')),
        findsOneWidget);
    expect(find.descendant(of: _card(2), matching: find.text('تعديل الإعلان')),
        findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('correction entry and existing resubmission action survive',
      (tester) async {
    final correction = _listing(1, 'إعلان يحتاج التصحيح',
        status: 'draft',
        review: 'returned_for_correction',
        reason: 'وضّح موقع العقار');
    final rejected = _listing(2, 'إعلان مرفوض سابق',
        status: 'rejected', review: 'rejected_duplicate', canEdit: false);
    await _open(tester, [correction, rejected],
        corrections: true, textScale: 2.1);
    expect(_card(1), findsOneWidget);
    expect(_card(2), findsNothing);
    expect(find.text('ملاحظة المراجعة: وضّح موقع العقار'), findsOneWidget);
    await tester.tap(find.byTooltip('خيارات البطاقة'));
    await tester.pumpAndSettle();
    expect(find.text('إعادة الإرسال'), findsOneWidget);
    expect(find.text('حذف'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
