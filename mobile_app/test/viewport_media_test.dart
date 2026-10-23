import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/widgets/viewport_media.dart';
import 'package:real_estate_mobile/features/account/data/auth_controller.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';
import 'package:real_estate_mobile/features/properties/data/listing_account_draft_repository.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_draft_photo.dart';

class _Guest extends AuthController {
  @override
  Future<AuthUser?> build() async => null;
}

class _Photos implements ListingAccountDraftRepository {
  int calls = 0;
  CancelToken? token;
  final pending = <Completer<Uint8List>>[];
  @override
  Future<Uint8List> photo(String url, {CancelToken? cancelToken}) {
    calls++;
    token = cancelToken;
    final done = Completer<Uint8List>();
    pending.add(done);
    cancelToken?.whenCancel.then((error) { if (!done.isCompleted) done.completeError(error); });
    return done.future;
  }
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
}

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

void main() {
  testWidgets('nested vertical and horizontal viewports never mount hidden media', (tester) async {
    final vertical = ScrollController(), horizontal = ScrollController();
    addTearDown(vertical.dispose);
    addTearDown(horizontal.dispose);
    final started = <int>[];
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: SizedBox(width: 300, height: 350,
      child: SingleChildScrollView(controller: vertical, child: Column(children: [
        const SizedBox(height: 1000),
        SizedBox(height: 150, child: ListView.builder(controller: horizontal, scrollDirection: Axis.horizontal,
          cacheExtent: 600, itemCount: 6, itemBuilder: (_, i) => SizedBox(width: 300,
            child: ViewportMedia(builder: (_) { started.add(i); return Text('media-$i'); })))),
        const SizedBox(height: 1000),
      ]))))));
    await _frames(tester);
    expect(started, isEmpty);
    vertical.jumpTo(950);
    await _frames(tester);
    expect(started.toSet(), {0});
    horizontal.jumpTo(900);
    await _frames(tester);
    expect(started.toSet(), {0, 3});
    expect(find.text('media-0'), findsNothing);
    expect(find.text('media-3'), findsOneWidget);
  });

  testWidgets('a retained hidden tab and a covered route suspend their network child', (tester) async {
    var selected = 0;
    late StateSetter change;
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(navigatorKey: navigator, home: StatefulBuilder(builder: (_, set) {
      change = set;
      return Scaffold(body: IndexedStack(index: selected, children: [
        for (var i = 0; i < 2; i++) TickerMode(enabled: selected == i,
          child: SizedBox(height: 120, child: ViewportMedia(builder: (_) => Text('tab-$i')))),
      ]));
    })));
    await _frames(tester);
    expect(find.text('tab-0'), findsOneWidget);
    expect(find.text('tab-1', skipOffstage: false), findsNothing);
    change(() => selected = 1);
    await _frames(tester);
    expect(find.text('tab-0', skipOffstage: false), findsNothing);
    expect(find.text('tab-1'), findsOneWidget);
    unawaited(navigator.currentState!.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('details')))));
    await tester.pumpAndSettle();
    expect(find.text('tab-1', skipOffstage: false), findsNothing);
    navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('tab-1'), findsOneWidget);
  });

  testWidgets('leaving the viewport releases and cancels a pending private image', (tester) async {
    final photos = _Photos(), scroll = ScrollController();
    addTearDown(scroll.dispose);
    await tester.pumpWidget(ProviderScope(overrides: [
      authControllerProvider.overrideWith(_Guest.new),
      listingAccountDraftRepositoryProvider.overrideWithValue(photos),
    ], child: MaterialApp(home: Scaffold(body: SingleChildScrollView(controller: scroll, child: Column(children: const [
      SizedBox(height: 120, child: ListingDraftPhoto(url: 'https://fixture.example/api/property-media/1')),
      SizedBox(height: 2000),
    ]))))));
    await _frames(tester);
    expect(photos.calls, 1);
    final first = photos.token!;
    scroll.jumpTo(1200);
    await _frames(tester);
    expect(first.isCancelled, isTrue);
    scroll.jumpTo(0);
    await _frames(tester);
    expect(photos.calls, 2);
    await tester.pumpWidget(const SizedBox());
    await _frames(tester);
    expect(tester.takeException(), isNull);
  });
}
