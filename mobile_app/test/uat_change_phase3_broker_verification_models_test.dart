import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/network/api_error_message.dart';
import 'package:real_estate_mobile/features/reviews/domain/listing_review_models.dart';

void main() {
  group('UAT Change Phase 3 broker verification', () {
    test('support review model parses required broker state', () {
      final item = ReviewListingItem.fromJson(<String, dynamic>{
        'id': 91,
        'title': 'عقار يحتاج تحقق',
        'purpose': 'sale',
        'type': 'house',
        'price': 1000000,
        'review_status': 'submitted',
        'owner': <String, dynamic>{'name': 'مستخدم'},
        'proof_documents': <dynamic>[
          <String, dynamic>{'id': 1}
        ],
        'broker_verification': <String, dynamic>{
          'required': true,
          'approval_allowed': false,
          'geo_cell_id': 7,
          'geo_cell_name': 'مربع حدة',
          'broker': <String, dynamic>{'id': 12, 'name': 'الدلال الرئيسي'},
          'latest': <String, dynamic>{
            'id': 33,
            'status': 'pending',
            'request_note': 'تحقق من حالة العقار',
          },
        },
      });

      expect(item.brokerVerification.required, true);
      expect(item.brokerVerification.approvalAllowed, false);
      expect(item.brokerVerification.brokerName, 'الدلال الرئيسي');
      expect(item.brokerVerification.latest?.isPending, true);
    });

    test('broker queue model contains listing metadata but no proof contract',
        () {
      final item = BrokerVerificationQueueItem.fromJson(<String, dynamic>{
        'id': 44,
        'status': 'pending',
        'geo_cell_name': 'مربع الاختبار',
        'listing': <String, dynamic>{
          'id': 101,
          'title': 'منزل',
          'purpose': 'sale',
          'type': 'house',
          'address': 'صنعاء',
          'area_value': 2,
          'area_unit': 'libna_sanaani',
          'area_m2': 89,
        },
      });

      expect(item.verification.id, 44);
      expect(item.listingId, 101);
      expect(item.areaUnit, 'libna_sanaani');
      expect(item.geoCellName, 'مربع الاختبار');
    });

    test('broker verification conflicts are translated to Arabic', () {
      final request = RequestOptions(path: '/phase3-test');
      final error = DioException(
        requestOptions: request,
        response: Response<Map<String, dynamic>>(
          requestOptions: request,
          statusCode: 409,
          data: <String, dynamic>{
            'message':
                'Official broker verification is required before approval.',
          },
        ),
        type: DioExceptionType.badResponse,
      );

      final message = friendlyApiError(error);
      expect(message, contains('الدلال الرئيسي'));
      expect(message, isNot(contains('Official broker')));
    });
  });
}
