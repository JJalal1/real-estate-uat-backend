import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/discovery/data/ai_repository.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_repository.dart';
import 'package:real_estate_mobile/features/discovery/data/marketplace_search_session.dart';
import 'package:real_estate_mobile/features/discovery/data/smart_search_session.dart';
import 'package:real_estate_mobile/features/discovery/domain/governorate_search.dart';
import 'package:real_estate_mobile/features/discovery/domain/smart_search_filters.dart';

import 'support/wave3_fakes.dart';

class _UnusedAuth implements AuthRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

void main() {
  const dhamar = HomeLocation(governorate: 'ذمار', governorateCode: 'DHAMAR',
      device: true, latitude: 14.55, longitude: 44.4);
  const sanaa = HomeLocation(governorate: 'صنعاء', governorateCode: 'SANAA', manual: true);
  test('confirmed province covers the entire region; an unresolved location never invents Sanaa', () {
    expect(dhamar.provinceSearchContext, {'governorate': 'ذمار', 'governorate_code': 'DHAMAR'});
    expect(dhamar.searchContext['radius_km'], 30);
    expect(const HomeLocation().provinceSearchContext, isEmpty);
    expect(const HomeLocation(device: true, needsConfirmation: true, governorate: 'ذمار').provinceSearchContext, isEmpty);
  });

  test('home and map use structured sale, rent and province for every property type', () async {
    final properties = Wave3PropertiesFake();
    final home = SmartSearchSession(Wave3AiFake(), properties);
    final map = SmartSearchSession(Wave3AiFake(), properties);
    final controller = MarketplaceSearchController(home, map, () => dhamar);
    addTearDown(() {controller.dispose(); home.dispose(); map.dispose();});
    for (final type in SmartSearchFilters.types.entries) {
      for (final purpose in {'للبيع': 'sale', 'للإيجار': 'rent'}.entries) {
        controller.edit('${type.value} ${purpose.key}');
        await controller.submit();
        expect(properties.queries.last.filters, {...dhamar.provinceSearchContext, 'type': type.key, 'purpose': purpose.value});
        controller.edit('${type.value} ${purpose.key} في محافظة صنعاء');
        await controller.submit();
        expect(properties.queries.last.filters, {...sanaa.provinceSearchContext, 'type': type.key, 'purpose': purpose.value});
      }
    }
    controller.enterMap();
    controller.edit('بيت للبيع في ذماء', onMap: true);
    await controller.submit(onMap: true);
    expect(map.snapshot.filters.apiFilters, {...dhamar.provinceSearchContext, 'purpose': 'sale', 'type': 'house'});
    expect(home.snapshot.filters.apiFilters['governorate_code'], 'SANAA');
  });

  test('smart typed and transcribed turns use the same province and pagination filters', () async {
    final dio = Dio();
    addTearDown(() => dio.close(force: true));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (r, handler) {
      final request = r.data as Map;
      final message = request['message'] as String;
      final values = Map<String, dynamic>.from(request['filters'] as Map);
      values.addAll({'purpose': 'rent', 'type': 'apartment'});
      if (message.contains('صنعاء')) values['search'] = 'صنعاء';
      if (message.contains('ذماء')) values['search'] = 'ذمار';
      if (message.contains('شارع')) values['search'] = 'شارع الجامعة';
      handler.resolve(Response(requestOptions: r, statusCode: 200,
        data: {'data': {'revision': request['revision'], 'filters': values}}));
    }));
    var current = const HomeLocation();
    final properties = Wave3PropertiesFake();
    final session = SmartSearchSession(AiRepository(dio, _UnusedAuth()), properties,
        defaultLocation: () => SmartSearchFilters.fromMap(current.provinceSearchContext));
    addTearDown(session.dispose);
    session.beginJourney();
    current = dhamar; // GPS resolves while the search composer is open.
    await session.interpret('شقة للإيجار');
    expect(properties.queries.last.filters, {...dhamar.provinceSearchContext, 'purpose': 'rent', 'type': 'apartment'});
    await session.interpret('شقة للإيجار في صنعاء');
    expect(properties.queries.last.filters, {...sanaa.provinceSearchContext, 'purpose': 'rent', 'type': 'apartment'});
    await session.interpret('في شارع الجامعة');
    expect(properties.queries.last.filters['governorate_code'], 'SANAA');
    expect(properties.queries.last.filters['search'], 'شارع الجامعة');
    current = sanaa;
    session.beginJourney();
    await session.interpret('شقة للإيجار في محافظة ذماء');
    expect(properties.queries.last.filters, {...dhamar.provinceSearchContext, 'purpose': 'rent', 'type': 'apartment'});
  });

  test('province and capital remain different and street names do not relocate the search', () {
    expect(GovernorateSearch.inRequest('أرض للبيع في أمانة العاصمة')!.filters['governorate_code'], 'AMANAT_AL_ASIMAH');
    expect(GovernorateSearch.inRequest('أرض للبيع في صنعاء')!.filters['governorate_code'], 'SANAA');
    expect(GovernorateSearch.inRequest('شقة في شارع تعز'), isNull);
  });
}
