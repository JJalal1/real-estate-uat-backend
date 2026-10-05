import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/account/data/auth_repository.dart';
import 'package:real_estate_mobile/features/properties/data/favorites_repository.dart';
import 'package:real_estate_mobile/features/properties/domain/favorite_list_item.dart';

class _FixtureAuth implements AuthRepository {
  String account = 'A';

  @override
  Future<Options> requiredAuthOptions() async =>
      Options(headers: {'Authorization': 'Bearer account-$account'});

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, dynamic> _saved(int id, String availability) => {
      'property_id': id,
      'is_favorited': true,
      'availability': availability,
      'favorited_at': '2026-10-05T12:00:00Z',
      if (availability == 'available')
        'property': {
          'id': id, 'status': 'published', 'title': 'Public property',
          'price': 15000000, 'currency': 'YER',
          'latitude': 15.3694, 'longitude': 44.1910,
        },
    };

void main() {
  test('repository preserves unavailable rows across pages with authentication',
      () async {
    final dio = Dio();
    final auth = _FixtureAuth();
    final pages = <int>[];
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      expect(request.path, '/favorites');
      expect(request.headers['Authorization'], 'Bearer account-A');
      final page = request.queryParameters['page'] as int;
      pages.add(page);
      handler.resolve(Response<Map<String, dynamic>>(
        requestOptions: request,
        statusCode: 200,
        data: {
          'data': [_saved(page, page == 1 ? 'available' : 'unavailable')],
          'meta': {'last_page': 2, 'total': 2},
        },
      ));
    }));
    final items = await FavoritesRepository(dio, auth).favorites();
    expect(pages, [1, 2]);
    expect(items.map((item) => item.propertyId), [1, 2]);
    expect(items.first.isAvailable, isTrue);
    expect(items.last.isAvailable, isFalse);
    expect(items.last.property, isNull);
    expect(items.last.favoritedAt, DateTime.utc(2026, 10, 5, 12));
  });

  test('IDs remain account state including unavailable IDs and account changes',
      () async {
    final dio = Dio();
    final auth = _FixtureAuth();
    final repository = FavoritesRepository(dio, auth);
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      expect(request.path, '/favorites/ids');
      handler.resolve(Response<Map<String, dynamic>>(
        requestOptions: request,
        data: {
          'data': {
            'property_ids': request.headers['Authorization'] == 'Bearer account-A'
                ? [1, 2] : <int>[],
          },
        },
      ));
    }));
    expect(await repository.favoriteIds(), {1, 2});
    auth.account = 'B';
    expect(await repository.favoriteIds(), isEmpty);
  });

  test('unavailable status is still saved and removal uses the account endpoint',
      () async {
    final dio = Dio();
    final auth = _FixtureAuth();
    final methods = <String>[];
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      expect(request.path, '/properties/42/favorite');
      expect(request.headers['Authorization'], 'Bearer account-A');
      methods.add(request.method);
      handler.resolve(Response<Map<String, dynamic>>(
        requestOptions: request,
        data: {'data': {
          'property_id': 42,
          'is_favorited': request.method == 'GET',
          'availability': 'unavailable',
        }},
      ));
    }));
    final repository = FavoritesRepository(dio, auth);
    expect(await repository.isFavorite(42), isTrue);
    await repository.remove(42);
    await repository.remove(42);
    expect(methods, ['GET', 'DELETE', 'DELETE']);
  });

  test('republished responses restore summary without another add request',
      () async {
    final dio = Dio();
    final auth = _FixtureAuth();
    var availability = 'unavailable';
    final methods = <String>[];
    dio.interceptors.add(InterceptorsWrapper(onRequest: (request, handler) {
      methods.add(request.method);
      handler.resolve(Response<Map<String, dynamic>>(
        requestOptions: request,
        data: {'data': [_saved(42, availability)], 'meta': {'last_page': 1}},
      ));
    }));
    final repository = FavoritesRepository(dio, auth);
    final before = (await repository.favorites()).single;
    availability = 'available';
    final after = (await repository.favorites()).single;
    expect(before.isAvailable, isFalse);
    expect(after.isAvailable, isTrue);
    expect(before.propertyId, after.propertyId);
    expect(before.favoritedAt, after.favoritedAt);
    expect(after.property!.title, 'Public property');
    expect(methods, ['GET', 'GET']);
  });

  test('unavailable and unknown states never parse even a published summary', () {
    for (final availability in ['unavailable', 'unknown']) {
      final row = _saved(42, 'available');
      row['availability'] = availability;
      final favorite = FavoriteListItem.fromJson(row);
      expect(favorite.isAvailable, isFalse);
      expect(favorite.property, isNull);
    }
  });

  test('available state requires a matching published summary', () {
    for (final status in ['draft', 'pending', 'rejected']) {
      final row = _saved(42, 'available');
      (row['property'] as Map<String, dynamic>)['status'] = status;
      expect(FavoriteListItem.fromJson(row).property, isNull);
    }
    final mismatched = _saved(42, 'available');
    (mismatched['property'] as Map<String, dynamic>)['id'] = 99;
    expect(FavoriteListItem.fromJson(mismatched).isAvailable, isFalse);
    expect(FavoriteListItem.fromJson(_saved(42, 'unavailable')).property, isNull);
  });

  test('legacy available response keeps existing public cards compatible', () {
    final row = _saved(42, 'available')..remove('availability')..remove('property_id');
    final favorite = FavoriteListItem.fromJson(row);
    expect(favorite.propertyId, 42);
    expect(favorite.isAvailable, isTrue);
    expect(favorite.property!.price, 15000000);
  });

  test('invalid identity is rejected without fabricating a property marker', () {
    expect(() => FavoriteListItem.fromJson({'availability': 'unavailable'}),
        throwsFormatException);
    expect(() => FavoriteListItem.fromJson({'property_id': 0}),
        throwsFormatException);
  });
}
