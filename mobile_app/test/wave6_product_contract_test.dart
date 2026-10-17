import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/properties/domain/property_schema.dart';
import 'package:real_estate_mobile/features/properties/domain/property_details.dart';
import 'package:real_estate_mobile/features/properties/domain/property_comparison.dart';
import 'package:real_estate_mobile/features/properties/domain/property_sai.dart';
import 'package:real_estate_mobile/features/discovery/data/smart_search_session.dart';
import 'package:real_estate_mobile/features/discovery/domain/smart_search_filters.dart';
import 'support/wave3_fakes.dart';
import 'support/wave6_fakes.dart';

void main(){
  test('shop fields, previous answers and rental apartment exclusions share the schema',(){
    final shop=DynamicPropertySchema.sanitize({'type':'shop','purpose':'rent','area_value':2,'area_unit':'libna_sanaani','floor_number':'3','unit_number':'7','has_parking':true,'building_facade':'north'});
    expect(shop['area_value'],closeTo(88.88,.001));expect(shop['area_unit'],'sqm');
    for(final key in ['floor_number','unit_number','has_parking','building_facade']){expect(shop.containsKey(key),isFalse);}
    expect(DynamicPropertySchema.required({'type':'shop','purpose':'rent'}),{'area_value'});
    expect(DynamicPropertySchema.floorOptions['0'],'الأرضي');expect(DynamicPropertySchema.floorOptions['3'],'الثالث');
    final rental=DynamicPropertySchema.sanitize({'type':'apartment','purpose':'rent','area_value':120,'has_elevator':true,'has_parking':false});
    expect(rental.keys,isNot(contains('area_value')));expect(rental.keys,isNot(contains('has_elevator')));expect(rental['has_parking'],false);
    expect(DynamicPropertySchema.sanitize({'type':'apartment','unit_occupies_entire_floor':true,'unit_number':'4'}).containsKey('unit_number'),isFalse);
  });
  test('modern listing payload clears nonapplicable data and allows an intentionally empty description',(){
    final input=PropertyListingInput(title:'محل للبيع',description:'',purpose:'sale',type:'shop',price:100,currency:'YER',latitude:15,longitude:44,
      areaValue:65,areaUnit:'sqm',floorNumber:'3',unitNumber:'4',hasParking:true,buildingFacade:'north',bedrooms:3);
    final data=input.toMap();expect(data['listing_input_version'],8);expect(data['description'],'');
    for(final key in ['floor_number','unit_number','has_parking','building_facade','bedrooms']){expect(data.containsKey(key),isFalse);}
    expect(SmartSearchFilters.fromMap({'type':'shop','floor_number':'3','has_parking':false,'min_area_m2':20}).values,{'type':'shop','min_area_m2':20});
  });
  test('comparison uses only real comparable money and known applicable facts',(){
    final a=wave6Property(11,price:10000000),b=wave6Property(12,price:12000000,area:160);
    final highlights=propertyComparisonHighlights([a,b]).join(' ');
    expect(highlights,contains('2000000'));expect(highlights,contains('40 م²'));expect(highlights, isNot(contains('الأفضل')));
    expect(propertyComparisonHighlights([a,wave6Property(12,currency:'USD')]).join(' '),isNot(contains('أقل سعرًا')));
    final missing=wave6Property(12,area:null);expect(propertyComparisonHighlights([a,missing]).join(' '),isNot(contains('أكبر مساحة')));
    final shop=wave6Property(13,type:'shop');expect(propertyComparisonFacts([shop,shop]).map((r)=>r.label),isNot(anyOf(contains('الدور'),contains('الموقف'),contains('الواجهة'))));
  });
  test('Sai preview follows actual server shares for professional and zero fallback',(){
    const policy=PropertySaiManagement(configured:false,advertiserType:'broker',fixedRatePercent:1,brokerMaxRatePercent:5,
      professionalPlatformSharePercent:17.5,fallbackPlatformSharePercent:100);
    expect(PropertySaiQuote.calculate(policy,2,100000)!.platform,350);
    expect(PropertySaiQuote.calculate(policy,0,100000)!.platform,1000);
    expect(PropertySaiQuote.calculate(policy,0,100000,fixedAmount:2000)!.platform,350);
  });
  test('full exit clears a journey and ignores delayed inference from that journey',()async{
    final pending=Completer<Map<String,dynamic>>(),ai=Wave3AiFake()..onRefine=(_,__,___)=>pending.future;
    final session=SmartSearchSession(ai,Wave3PropertiesFake());addTearDown(session.dispose);
    final token=session.beginJourney();session.setDraftText('طلب خاص');final revision=session.state.revision;
    final work=session.interpret('محل');session.endJourney(token);await Future<void>.delayed(Duration.zero);
    pending.complete({'revision':revision,'filters':{'type':'shop'}});await work;
    expect(session.state.filters.values,isEmpty);expect(session.state.rows,isEmpty);expect(session.state.draftText,isEmpty);
  });
  test('explicit saved search can restore and old disposal cannot clear a new journey',()async{
    final session=SmartSearchSession(Wave3AiFake(),Wave3PropertiesFake());addTearDown(session.dispose);
    final first=session.beginJourney();session.endJourney(first);
    session.beginJourney(savedFilters:SmartSearchFilters.fromMap({'type':'land','search':'تعز'}));await Future<void>.delayed(Duration.zero);
    expect(session.state.filters.values['search'],'تعز');
  });
  test('viewport replaces the old geographic circle and preserves text, currency and source constraints',()async{
    final properties=Wave3PropertiesFake();
    final session=SmartSearchSession(Wave3AiFake(),properties);addTearDown(session.dispose);
    session.beginJourney(savedFilters:SmartSearchFilters.fromApiFilters({'type':'apartment','purpose':'rent','currency':'USD','max_monthly_rent':400,
      'has_parking':0,'latitude':15,'longitude':44,'radius_km':20,'advertiser_id':9,'area_polygon':'[[44,15],[45,15],[44,16],[44,15]]'}));
    session.setDraftText('طلب مكتوب');session.updateViewport(south:15,west:44,north:16,east:45);await Future<void>.delayed(Duration.zero);
    expect(session.state.draftText,'طلب مكتوب');expect(session.state.filters.values['advertiser_id'],9);
    expect(session.state.filters.apiFilters['max_monthly_rent'],400);expect(session.state.filters.apiFilters['has_parking'],0);
    expect(session.state.filters.values.containsKey('radius_km'),isFalse);expect(session.state.filters.values.containsKey('area_polygon'),isTrue);
    expect(properties.queries.last.filters['south'],15);expect(properties.queries.last.filters['currency'],'USD');
  });
}
