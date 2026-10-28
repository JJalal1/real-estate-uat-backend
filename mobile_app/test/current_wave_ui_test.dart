import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:real_estate_mobile/features/discovery/data/ai_repository.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_repository.dart';
import 'package:real_estate_mobile/features/discovery/presentation/marketplace_home_screen.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_editor_screen.dart';
import 'package:real_estate_mobile/core/widgets/app_select_field.dart';
import 'support/wave3_fakes.dart';
import 'support/wave6_fakes.dart';
import 'current_wave_contract_test.dart' show MemoryLocationStore, FakeLocationAccess;
import 'wave6_product_ui_test.dart' show pumpWave6,finishWave6,editorSnapshot,previewWave6;

class CountingDescriptionAi extends Wave6Ai {
  int calls=0;
  bool rateLimited=false;
  Completer<Map<String,dynamic>>? pending;
  @override
  Future<Map<String,dynamic>> description(Map<String,dynamic> facts,{int? propertyId,String? draftKey, String sourceDescription = ''}) async {
    calls++;
    if(rateLimited) { descriptionRetryAt=DateTime.now().add(const Duration(seconds:30));throw DescriptionRateLimit(descriptionRetryAt!); }
    return pending?.future??Future.value({'description':'منزل للبيع من الحقائق المدخلة.'});
  }
}
void main() {
  for(final scale in [1.0,2.4]) {
    testWidgets('current wave Sai defaults to fixed, spells the amount and caps percentages at scale $scale',(tester) async {
      final snapshot=editorSnapshot()..['step']=3,boundary=GlobalKey();
      await pumpWave6(tester,const ListingEditorScreen(),recovery:Wave6Recovery(snapshot),scale:scale,boundary:boundary);
      final fixed=find.byKey(const ValueKey('listing-sai-fixed')),amount=find.byKey(const ValueKey('listing-sai-amount'));
      expect(tester.widget<ChoiceChip>(fixed).selected,true);expect(find.byKey(const ValueKey('listing-sai-rate')),findsNothing);
      await tester.ensureVisible(amount);await tester.enterText(amount,'١٠٠٠٠٠');await tester.pumpAndSettle();
      expect(find.text('مائة ألف ريال يمني'),findsOneWidget);expect(find.text('حصة المنصة تُحتسب على الدلال'),findsOneWidget);
      await tester.ensureVisible(find.text('حصة المنصة تُحتسب على الدلال'));await previewWave6(tester,boundary,'wave6-current-fixed-$scale');
      final percentage=find.byKey(const ValueKey('listing-sai-percentage'));
      await tester.ensureVisible(percentage);await tester.tap(percentage);await tester.pumpAndSettle();
      final rate=find.byKey(const ValueKey('listing-sai-rate'));await tester.ensureVisible(rate);await tester.enterText(rate,'101');await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('listing-sai-amount')),findsNothing);expect(find.text('أقصى نسبة للسعي 100%'),findsOneWidget);
      await previewWave6(tester,boundary,'wave6-current-rate-limit-$scale');expect(tester.takeException(),isNull);await finishWave6(tester);
    });
    testWidgets('current wave apartment floor selector contains exactly ground through seven at scale $scale',(tester)async {
      final snapshot=editorSnapshot(type:'apartment');(snapshot['fields'] as Map)['floor_number']='7';
      await pumpWave6(tester,const ListingEditorScreen(),recovery:Wave6Recovery(snapshot),scale:scale);
      final field=tester.widget<AppSelectField<String>>(find.byKey(const ValueKey('listing-floor-select')));
      // Inspect the actual controlled field used by the editor.
      expect(field.items.map((item)=>item.value),['0','1','2','3','4','5','6','7']);
      expect(field.value,'7');expect(tester.takeException(),isNull);await finishWave6(tester);
    });
  }
  testWidgets('description double tap is one request and rate limiting stays inline without automatic retries',(tester)async {
    final ai=CountingDescriptionAi()..pending=Completer<Map<String,dynamic>>();
    await pumpWave6(tester,const ListingEditorScreen(),ai:ai,recovery:Wave6Recovery(editorSnapshot()));
    final button=find.byKey(const ValueKey('listing-description-generate'));
    await tester.ensureVisible(button);await tester.tap(button);await tester.pump();await tester.tap(button);await tester.pump();
    expect(ai.calls,1);expect(find.byType(BottomSheet),findsNothing);expect(find.byType(Dialog),findsNothing);
    ai.pending!.complete({'description':'منزل للبيع.'});await tester.pumpAndSettle();ai.pending=null;ai.rateLimited=true;
    await tester.ensureVisible(button);await tester.tap(button);await tester.pumpAndSettle();
    expect(find.text('تعذر إنشاء الوصف الآن، جرّب بعد لحظات'),findsOneWidget);
    expect(tester.widget<TextButton>(button).onPressed,isNull);await tester.pump(const Duration(seconds:2));expect(ai.calls,2);
    expect(tester.takeException(),isNull);await finishWave6(tester);
  });
  testWidgets('explicit home location permission updates the real feed query and manual city persists',(tester)async {
    final store=MemoryLocationStore(),access=FakeLocationAccess()..decision=LocationPermission.whileInUse;
    final repository=Wave3MarketplaceFake(onFeed:(q)async=>MarketplaceFeed(label:q.governorate??(q.device?'عدن':'صنعاء')));
    await pumpWave6(tester,const MarketplaceHomeScreen(),allowLocation:true,locationStore:store,locationAccess:access,marketplace:repository);
    expect(access.requests,0);expect(repository.queries.last.device,false);
    expect(find.byKey(const ValueKey('location-introduction-device')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('location-introduction-device')));await tester.pumpAndSettle();
    expect(access.requests,1);expect(repository.queries.last.device,true);expect(repository.queries.last.latitude,12.8);expect(find.text('عدن'),findsOneWidget);
    await tester.tap(find.text('الموقع'));await tester.pumpAndSettle();await tester.tap(find.text('تعز'));await tester.pumpAndSettle();
    expect(repository.queries.last.governorate,'تعز');expect(store.value.manual!.governorate,'تعز');expect(access.requests,1);
    expect(tester.takeException(),isNull);await finishWave6(tester);
  });
}

