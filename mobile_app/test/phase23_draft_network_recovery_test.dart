import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:real_estate_mobile/features/properties/domain/listing_account_draft.dart';
import 'package:real_estate_mobile/features/properties/presentation/listing_editor_screen.dart';
import 'support/owner_ux_fixtures.dart' show loadUxFixtures;
import 'support/wave6_fakes.dart';
import 'wave6_product_ui_test.dart' show pumpWave6, finishWave6, editorSnapshot, textField;

enum _Failure { beforeWrite, afterWrite, otherWriter }

class _DisconnectedDrafts extends Wave6Drafts {
  _DisconnectedDrafts(this.failure);
  final _Failure failure;
  bool online = true, injected = false;
  int disconnections = 0;
  DioException get offline => DioException(
    requestOptions: RequestOptions(path: '/listing-editor-drafts/synthetic'),
    type: DioExceptionType.connectionError, message: 'Synthetic disconnected network');

  @override
  Future<ListingAccountDraft> get(String key) async {
    if (!online) throw offline;
    return super.get(key);
  }

  @override
  Future<ListingAccountDraft> save(String key, Map<String, dynamic> payload,
      int revision, {int? propertyId}) async {
    if (online) return super.save(key, payload, revision, propertyId: propertyId);
    disconnections++;
    if (!injected) {
      injected = true;
      if (failure == _Failure.afterWrite) {
        await super.save(key, payload, revision, propertyId: propertyId);
      } else if (failure == _Failure.otherWriter) {
        final old = drafts[key]!;
        final other = Map<String, dynamic>.from(jsonDecode(jsonEncode(old.payload)) as Map);
        other['checkpoint_key'] = 'synthetic-other-device-checkpoint';
        (other['fields'] as Map)['description'] = 'تعديل من جهاز آخر';
        drafts[key] = ListingAccountDraft(key: key, revision: old.revision + 1,
          payload: other, images: old.images, propertyId: old.propertyId);
      }
    }
    throw offline;
  }
}

void main() {
  setUpAll(loadUxFixtures);
  for (final failure in _Failure.values) {
    testWidgets('account draft reconnect preserves revision safety: ${failure.name}',
        (tester) async {
      final drafts = _DisconnectedDrafts(failure), key = newListingDraftKey();
      final draft = ListingAccountDraft(key: key, revision: 7,
        payload: {...editorSnapshot(), 'editor_version': 11,
          'draft_kind': 'recovery', 'entry_method': 'manual'},
        title: 'مسودة اصطناعية', progress: 80);
      drafts.drafts[key] = draft;
      await pumpWave6(tester, ListingEditorScreen(accountDraft: draft), drafts: drafts);
      try {
        await tester.ensureVisible(textField('وصف العقار'));
        final before = drafts.drafts[key]!;
        final savesBefore = drafts.saves.length;
        drafts.online = false;
        await tester.enterText(textField('وصف العقار'), 'وصف اصطناعي محفوظ دون اتصال');
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
        expect(drafts.disconnections, greaterThan(0));
        expect(find.textContaining('تعذر الحفظ على الحساب'), findsOneWidget);
        if (failure == _Failure.beforeWrite) {
          expect(drafts.drafts[key]!.revision, before.revision);
          expect((drafts.drafts[key]!.payload['fields'] as Map)['description'],
            isNot('وصف اصطناعي محفوظ دون اتصال'));
        }
        drafts.online = true;
        await tester.ensureVisible(find.text('إعادة محاولة الحفظ'));
        await tester.tap(find.text('إعادة محاولة الحفظ'));
        await tester.pumpAndSettle();
        const conflict = 'تغيرت المسودة على جهاز آخر. افتح أحدث نسخة قبل المتابعة.';
        if (failure == _Failure.otherWriter) {
          expect(find.text(conflict), findsOneWidget);
          expect(drafts.drafts[key]!.revision, before.revision + 1);
          expect((drafts.drafts[key]!.payload['fields'] as Map)['description'], 'تعديل من جهاز آخر');
          expect(drafts.saves.length, savesBefore);
        } else {
          expect(find.text(conflict), findsNothing);
          expect(find.text('حُفظ تقدمك وصورك على حسابك'), findsOneWidget);
          expect((drafts.drafts[key]!.payload['fields'] as Map)['description'],
            'وصف اصطناعي محفوظ دون اتصال');
          expect(drafts.drafts[key]!.revision, greaterThan(before.revision));
        }
        expect(tester.takeException(), isNull);
      } finally {
        await finishWave6(tester);
      }
    });
  }
}
