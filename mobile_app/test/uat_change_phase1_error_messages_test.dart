import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/core/network/api_error_message.dart';

void main() {
  DioException responseError(int statusCode, Map<String, dynamic> data) {
    final request = RequestOptions(path: '/phase1-test');
    return DioException(
      requestOptions: request,
      response: Response<Map<String, dynamic>>(
        requestOptions: request,
        statusCode: statusCode,
        data: data,
      ),
      type: DioExceptionType.badResponse,
    );
  }

  test('Phase 1 maps duplicate content report conflict to Arabic', () {
    final message = friendlyApiError(
      responseError(409, {
        'message': 'An open report for this target already exists.',
      }),
    );
    expect(message, contains('بلاغ مفتوح بالفعل'));
    expect(message, isNot(contains('already exists')));
  });

  test('Phase 1 does not leak English validation errors to the UI', () {
    final message = friendlyApiError(
      responseError(422, {
        'message': 'The given data was invalid.',
        'errors': {
          'details': ['The details field must be at least 5 characters.'],
        },
      }),
    );
    expect(message, 'اكتب تفاصيل واضحة للبلاغ لا تقل عن 5 أحرف.');
  });

  test('Phase 1 maps self conversation validation to Arabic', () {
    final message = friendlyApiError(
      responseError(422, {
        'errors': {
          'property_id': ['You cannot start a conversation with yourself.'],
        },
      }),
    );
    expect(message, 'لا يمكنك بدء محادثة مع نفسك.');
  });

  test('Phase 1 maps account activation errors to Arabic', () {
    final message = friendlyApiError(
      responseError(403, {
        'code': 'ACCOUNT_NOT_ACTIVE',
        'message': 'Account not active.',
      }),
    );
    expect(message, contains('تحقق من رقم الهاتف'));
  });
}
