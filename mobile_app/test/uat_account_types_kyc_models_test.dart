import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/account/domain/account_verification.dart';
import 'package:real_estate_mobile/features/account/domain/auth_user.dart';

void main() {
  test('base account is a researcher/browser/buyer and cannot publish', () {
    final user = AuthUser.fromJson({
      'id': 10,
      'name': 'أحمد محمد علي صالح',
      'email': 'wa_hidden@phone.local.invalid',
      'phone': '+967711111101',
      'account_type': 'regular',
      'account_status': 'active',
      'phone_verified_at': '2026-08-29T00:00:00Z',
      'profile_completed_at': '2026-08-29T00:01:00Z',
      'broker_verification_status': 'not_required',
      'verification_profile': {
        'type': null,
        'status': 'not_submitted',
        'flags': <String, bool>{},
      },
      'is_platform_owner': false,
      'roles': ['registered_user'],
      'permissions': <String>[],
    });

    expect(user.needsProfileCompletion, isFalse);
    expect(user.hasVerifiedPublishingProfile, isFalse);
    expect(user.canCreateListing, isFalse);
    expect(user.accountTypeLabel, 'باحث / متصفح / مشتري');
  });

  test('approved owner account can create listing after account identity review',
      () {
    final user = AuthUser.fromJson({
      'id': 11,
      'name': 'أحمد محمد علي صالح',
      'phone': '+967711111102',
      'account_type': 'regular',
      'account_status': 'active',
      'phone_verified_at': '2026-08-29T00:00:00Z',
      'profile_completed_at': '2026-08-29T00:01:00Z',
      'verification_profile': {
        'type': 'owner',
        'status': 'approved',
        'reviewed_at': '2026-08-29T00:02:00Z',
        'flags': {'identity_reviewed': true},
      },
      'is_platform_owner': false,
      'roles': ['registered_user'],
      'permissions': <String>[],
    });

    expect(user.isOwner, isTrue);
    expect(user.verificationProfile.identityReviewed, isTrue);
    expect(user.canCreateListing, isTrue);
    expect(user.accountTypeLabel, 'مالك');
  });

  test('broker professional label requires approved professional document', () {
    final user = AuthUser.fromJson({
      'id': 12,
      'name': 'محمد أحمد علي صالح',
      'phone': '+967711111103',
      'account_type': 'regular',
      'account_status': 'active',
      'phone_verified_at': '2026-08-29T00:00:00Z',
      'profile_completed_at': '2026-08-29T00:01:00Z',
      'verification_profile': {
        'type': 'broker',
        'status': 'approved',
        'reviewed_at': '2026-08-29T00:02:00Z',
        'flags': {
          'identity_reviewed': true,
          'professional_document_reviewed': true,
        },
      },
      'is_platform_owner': false,
      'roles': ['registered_user'],
      'permissions': <String>[],
    });

    expect(user.isBroker, isTrue);
    expect(user.isBrokerVerified, isTrue);
    expect(user.canCreateListing, isTrue);
    expect(user.accountTypeLabel, 'دلال مهني');
  });

  test('office verification application parses required trust flags', () {
    final application = AccountVerificationApplication.fromJson({
      'user_id': 13,
      'name': 'خالد محمد علي حسن',
      'phone': '+967711111104',
      'type': 'office',
      'status': 'approved',
      'reviewed_at': '2026-08-29T00:02:00Z',
      'details': {
        'office_name': 'مكتب الثقة للعقارات',
        'governorate': 'صنعاء',
        'district': 'معين',
        'latitude': 15.33,
        'longitude': 44.17,
      },
      'documents': [
        {'kind': 'responsible_identity', 'original_name': 'id.jpg'},
        {'kind': 'selfie', 'original_name': 'selfie.jpg'},
        {'kind': 'commercial_register', 'original_name': 'cr.jpg'},
        {'kind': 'office_license', 'original_name': 'license.jpg'},
        {'kind': 'office_frontage', 'original_name': 'front.jpg'},
      ],
      'verification_flags': {
        'identity_reviewed': true,
        'commercial_register_reviewed': true,
        'office_documents_reviewed': true,
        'office_location_registered': true,
      },
    });

    expect(application.typeLabel, 'مكتب عقارات');
    expect(application.approved, isTrue);
    expect(application.hasDocument('commercial_register'), isTrue);
    expect(application.verificationFlags['office_location_registered'], isTrue);
  });

  test('mobile login source exposes one WhatsApp flow without account type selector',
      () async {
    final source = await File('lib/features/account/presentation/auth_screen.dart')
        .readAsString();
    expect(source.contains('حساب واحد للجميع'), isTrue);
    expect(source.contains('رقم واتساب'), isTrue);
    expect(source.contains('مستخدم عادي'), isFalse);
    expect(source.contains('DropdownButtonFormField'), isFalse);
  });

  test('verification selfie offers camera capture or an existing file',
      () async {
    final pickerSource =
        await File('lib/core/platform/stage5_media_picker.dart').readAsString();
    final verificationSource = await File(
            'lib/features/account/presentation/account_verification_screen.dart')
        .readAsString();
    final androidSource = await File(
            'android/app/src/main/kotlin/com/example/real_estate_mobile/MainActivity.kt')
        .readAsString();

    expect(pickerSource.contains("invokeMethod<String>('takePhoto')"), isTrue);
    expect(pickerSource.contains("invokeListMethod<String>('pickImages')"), isTrue);
    expect(verificationSource.contains("kind == 'selfie'"), isTrue);
    expect(verificationSource.contains('_chooseSelfieSource()'), isTrue);
    expect(verificationSource.contains('_picker.takePhoto()'), isTrue);
    expect(verificationSource.contains('_picker.pickImages()'), isTrue);
    expect(verificationSource.contains('فتح الكاميرا'), isTrue);
    expect(verificationSource.contains('اختيار من الملفات'), isTrue);
    expect(androidSource.contains('MediaStore.ACTION_IMAGE_CAPTURE'), isTrue);
    expect(androidSource.contains('Intent.ACTION_OPEN_DOCUMENT'), isTrue);
  });
}
