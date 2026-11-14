"""Boundary and evidence tests; no network, database, emulator or business writes."""
from copy import deepcopy
import hashlib
import json
from pathlib import Path
import struct
import sys
import tempfile
import time
import unittest
from unittest.mock import Mock, patch
from xml.sax.saxutils import escape
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import run_phase23_local_media_journey as c
from phase23_preflight import GateError

ENV = {'GITHUB_RUN_ID': '43499999999', 'GITHUB_SHA': 'a' * 40}
ORIGIN = 'http://10.0.2.2:8000'


def fixture():
    nonce = 'b' * 32
    files = []
    for name, kind, digest_number in (('A-exterior.png', 'good', 1),
                                      ('B-interior.png', 'good', 2),
                                      ('C-replacement.jpg', 'good', 4),
                                      ('X-brand-logo.png', 'bad', 3)):
        files.append({'name': name, 'path': '/tmp/phase23-local-media/files/' + name,
                      'source': 'fixture/' + name, 'sha256': str(digest_number) * 64, 'kind': kind})
    return {'schema': 1, 'marker': c.MARKER, 'nonce': nonce, 'api': c.API, 'app_env': 'local',
            'origin': ORIGIN, 'database': c.DATABASE, 'run_id': ENV['GITHUB_RUN_ID'],
            'source_sha': ENV['GITHUB_SHA'], 'product_trees': dict(c.TREES),
            'identity_path': '/phase23-local-identity-' + nonce + '.json',
            'actors': {alias: {'id': index + 1, 'phone': c.PHONES[alias],
                              'email': 'p23-local-' + alias + '@example.test'}
                       for index, alias in enumerate(c.ACTORS)},
            'listing_id': 71, 'title': 'P23 Local Media Original',
            'updated_title': 'P23 Local Media Updated', 'files': files}


def photo(number, index=0, primary=None, relevance='unreviewed'):
    return {'id': number, 'sha256': str(number) * 64, 'sort_order': index,
            'is_primary': index == 0 if primary is None else primary,
            'relevance_status': relevance, 'fingerprint': 'f' * 64, 'review': None}


def snapshot(images=None, **changes):
    f = fixture()
    listing = {'id': f['listing_id'], 'title': f['title'], 'status': 'draft',
               'review_status': 'draft', 'last_review_reason': None,
               'images': deepcopy(images or []), 'reviews': []}
    listing.update(changes)
    return {'marker': c.MARKER, 'nonce': f['nonce'], 'app_env': 'local',
            'api_origin': ORIGIN, 'database': c.DATABASE, 'user_count': 3,
            'property_count': 1, 'listing': listing, 'audit_events': []}


def review(number, action, actor='support', **metadata):
    return {'id': number, 'action': action, 'actor_user_id': fixture()['actors'][actor]['id'],
            'metadata': metadata}


def node(label, box='[20,200][1000,350]', **changes):
    attrs = {'package': c.PACKAGE, 'text': label, 'bounds': box,
             'enabled': 'true', 'clickable': 'true', 'visible-to-user': 'true',
             'class': 'android.widget.Button'}
    attrs.update(changes)
    return '<node ' + ' '.join(key + '="' + escape(str(value), {'"': '&quot;'}).replace('\n', '&#10;') + '"'
                              for key, value in attrs.items()) + ' />'


def screen(*nodes):
    return '<hierarchy>' + ''.join(nodes or [node('حسابي')]) + '</hierarchy>'


class FixtureBoundaryTests(unittest.TestCase):
    def test_disposable_fixture_is_tied_to_source_run_nonce_and_origins(self):
        value = fixture()
        self.assertIs(c.validate_fixture(value, ENV), value)
        for key, bad in [('api', 'https://real-estate-uat-api-frankfurt.onrender.com/api'),
                         ('origin', 'http://127.0.0.1:8001'), ('database', 'postgres'),
                         ('run_id', '43400000000'), ('source_sha', 'c' * 40),
                         ('nonce', '../private'), ('identity_path', '/identity.json'),
                         ('schema', 2), ('marker', 'ORDINARY_UAT'), ('app_env', 'uat'),
                         ('app_env', None)]:
            value = fixture(); value[key] = bad
            with self.subTest(key=key), self.assertRaises(GateError):
                c.validate_fixture(value, ENV)

    def test_only_three_exact_local_actor_slots_are_allowed(self):
        variants = []
        value = fixture(); value['actors']['advertiser']['phone'] = '+967777777777'; variants.append(value)
        value = fixture(); value['actors']['support']['email'] = 'staff@example.com'; variants.append(value)
        value = fixture(); value['actors']['researcher']['id'] = value['actors']['support']['id']; variants.append(value)
        value = fixture(); value['actors']['support']['id'] = True; variants.append(value)
        value = fixture(); value['actors']['admin'] = value['actors']['support']; variants.append(value)
        value = fixture(); value['actors']['support']['token'] = 'must-not-be-imported'; variants.append(value)
        for value in variants:
            with self.subTest(value=value['actors']), self.assertRaises(GateError):
                c.validate_fixture(value, ENV)

    def test_source_media_is_bounded_and_titles_cannot_be_arbitrary_commands(self):
        variants = []
        value = fixture(); value['files'].append(deepcopy(value['files'][0])); variants.append(value)
        value = fixture(); value['files'][0]['name'] = '../outside.png'; variants.append(value)
        value = fixture(); value['files'][0]['path'] = 'relative.png'; variants.append(value)
        value = fixture(); value['files'][1]['name'] = value['files'][0]['name']; variants.append(value)
        value = fixture(); value['files'][3]['kind'] = 'good'; variants.append(value)
        value = fixture(); value['files'][0]['sha256'] = 'not-a-digest'; variants.append(value)
        value = fixture(); value['updated_title'] = value['title']; variants.append(value)
        value = fixture(); value['title'] = 'P23 $(read-private)'; variants.append(value)
        for value in variants:
            with self.subTest(value=value), self.assertRaises(GateError):
                c.validate_fixture(value, ENV)

    def test_compiled_endpoint_and_build_identity_are_both_required(self):
        with tempfile.TemporaryDirectory() as directory:
            apk = Path(directory) / 'local.apk'
            with zipfile.ZipFile(apk, 'w') as archive:
                archive.writestr('assets/flutter_assets/kernel_blob.bin', b'compiled ' + c.API.encode())
            receipt = {'marker': 'AQER_LOCAL_MEDIA_BUILD_V1', 'schema': 1,
                       'target': 'lib/main.dart', 'mode': 'debug', 'environment': 'local',
                       'flavor': 'uat', 'run_id': ENV['GITHUB_RUN_ID'], 'database': c.DATABASE,
                       'share_base': ORIGIN, 'compiled_local_endpoint': True, 'provider_overrides': False,
                       'api': c.API, 'package': c.PACKAGE, 'source_sha': ENV['GITHUB_SHA'],
                       'product_trees': c.TREES, 'apk_sha256': c.digest(apk)}
            c.verify_build(apk, receipt, fixture())
            for key, bad in [('target', 'lib/phase23_private_pages_main.dart'), ('mode', 'release'),
                             ('environment', 'uat'), ('api', 'https://remote.example/api'),
                             ('package', 'com.example.other'), ('source_sha', 'c' * 40),
                             ('product_trees', {}), ('apk_sha256', '0' * 64),
                             ('marker', 'ORDINARY_UAT'), ('schema', 2), ('flavor', 'prod'),
                             ('run_id', '43400000000'), ('database', 'postgres'),
                             ('share_base', 'https://remote.example'), ('compiled_local_endpoint', False),
                             ('provider_overrides', True)]:
                changed = deepcopy(receipt); changed[key] = bad
                with self.subTest(key=key), self.assertRaises(GateError):
                    c.verify_build(apk, changed, fixture())
            for key in receipt:
                changed = deepcopy(receipt); del changed[key]
                with self.subTest(missing=key), self.assertRaises(GateError):
                    c.verify_build(apk, changed, fixture())
            with zipfile.ZipFile(apk, 'w') as archive:
                archive.writestr('assets/flutter_assets/kernel_blob.bin', b'https://remote.example/api')
            receipt['apk_sha256'] = c.digest(apk)
            with self.assertRaisesRegex(GateError, 'compiled_api_missing'):
                c.verify_build(apk, receipt, fixture())


class NativeInputBoundaryTests(unittest.TestCase):
    def test_only_current_allowlisted_app_or_picker_surface_is_accepted(self):
        c.ui_nodes(screen(), {c.PACKAGE})
        picker = 'com.android.documentsui'
        value = screen(node('Open', package=picker))
        c.ui_nodes(value, {c.PACKAGE, picker})
        for bad in (value, screen(node('foreign', package='com.attacker')),
                    '<!DOCTYPE hierarchy>' + screen(), '<!ENTITY x "value">' + screen(),
                    '<not-hierarchy/>', '<hierarchy/>'):
            with self.subTest(xml=bad), self.assertRaises(c.Incomplete):
                c.ui_nodes(bad, {c.PACKAGE})

    def test_repeated_labels_require_explicit_visible_ordinal(self):
        value = screen(node('خيارات الصورة', '[800,300][1000,450]'),
                       node('خيارات الصورة', '[500,300][700,450]'))
        with self.assertRaisesRegex(c.Incomplete, 'ambiguous'):
            c.select_control(value, 'خيارات الصورة', {c.PACKAGE})
        self.assertEqual(c.select_control(value, 'خيارات الصورة', {c.PACKAGE}, ordinal=0), (800,300,1000,450))
        self.assertEqual(c.select_control(value, 'خيارات الصورة', {c.PACKAGE}, ordinal=1), (500,300,700,450))
        for index in (-1, 2, True):
            with self.subTest(index=index), self.assertRaises(c.Incomplete):
                c.select_control(value, 'خيارات الصورة', {c.PACKAGE}, ordinal=index)

    def test_disabled_hidden_offscreen_and_unbound_input_are_not_clickable(self):
        variants = [screen(node('Next', enabled='false')),
                    screen(node('Next', **{'visible-to-user':'false'})),
                    screen(node('Next', '[0,0][1081,1920]')),
                    screen(node('Next', clickable='false'))]
        for value in variants:
            with self.subTest(xml=value), self.assertRaises(c.Incomplete):
                c.select_control(value, 'Next', {c.PACKAGE})
        with self.assertRaises(c.Incomplete):
            c.select_control(screen(node('Phone')), 'Phone', {c.PACKAGE}, editable=True)
        value = screen(node('Phone', **{'class':'android.widget.EditText', 'clickable':'false'}))
        self.assertEqual(c.select_control(value,'Phone',{c.PACKAGE},editable=True),(20,200,1000,350))

    def test_moving_control_refuses_delivery_instead_of_repeating_input(self):
        device = Mock(); journey = c.Journey(device, fixture(), Path('/tmp/fixture.json'), Path('/tmp/evidence'))
        first = screen(node('Next', '[20,200][1000,350]'))
        moved = screen(node('Next', '[20,350][1000,500]'))
        with patch.object(journey, 'xml', side_effect=[first, moved]), patch.object(c.time, 'sleep'):
            with self.assertRaisesRegex(c.Incomplete, 'control_moved'):
                journey.tap('Next')
        device.adb.assert_not_called()
        self.assertEqual(journey.inputs, 0)

    def test_ambiguous_or_foreign_surface_never_uses_seek_to_retry_write(self):
        for value in (screen(node('Next'),node('Next','[20,500][1000,650]')),
                      screen(node('Next',package='com.other.app'))):
            device=Mock(); journey=c.Journey(device,fixture(),Path('/tmp/fixture.json'),Path('/tmp/evidence'))
            with patch.object(journey,'xml',return_value=value), patch.object(journey,'scroll') as scroll:
                with self.assertRaises(c.Incomplete): journey.tap('Next',seek=4)
            scroll.assert_not_called(); device.adb.assert_not_called()

    def test_review_button_is_bound_to_the_numbered_photo_not_global_ordinal(self):
        value=screen(node('الصورة 1 — غير محسومة','[20,300][1000,340]',clickable='false'),
                     node('تسجيل المراجعة البشرية','[20,700][1000,770]'),
                     node('الصورة 2 — غير محسومة','[20,850][1000,890]',clickable='false'),
                     node('تسجيل المراجعة البشرية','[20,1100][1000,1170]'))
        self.assertEqual(c.select_review_control(value,1,{c.PACKAGE}),(20,700,1000,770))
        self.assertEqual(c.select_review_control(value,2,{c.PACKAGE}),(20,1100,1000,1170))
        for number in (0,3,True):
            with self.subTest(number=number),self.assertRaises(c.Incomplete):c.select_review_control(value,number,{c.PACKAGE})
        for bad in (value.replace('الصورة 2 — غير محسومة','الصورة 3 — غير محسومة'),
                    value.replace('</hierarchy>',node('تسجيل المراجعة البشرية','[20,1250][1000,1320]')+'</hierarchy>'),
                    value.replace('[20,1100][1000,1170]','[20,700][1000,770]')):
            with self.subTest(xml=bad),self.assertRaises(c.Incomplete):c.select_review_control(bad,2,{c.PACKAGE})

    def test_drag_uses_two_visible_rtl_cards_in_one_observed_horizontal_viewport(self):
        viewport=node('photos','[20,400][1060,900]',scrollable='true',clickable='false')
        value=screen(viewport,node('خيارات الصورة','[930,450][1000,510]'),node('إزالة الصورة','[780,450][850,510]'),
                     node('خيارات الصورة','[570,450][640,510]'),node('إزالة الصورة','[420,450][490,510]'))
        self.assertEqual(c.media_drag_targets(value,{c.PACKAGE}),((890,530),(530,530)))
        variants=[value.replace('</hierarchy>',viewport+'</hierarchy>'),
                  value.replace('[420,450][490,510]','[20,450][90,510]'),
                  value.replace('[420,450][490,510]','[420,480][490,540]'),
                  value.replace('scrollable="true"','scrollable="false"'),
                  value.replace('إزالة الصورة','unknown control')]
        for bad in variants:
            with self.subTest(xml=bad),self.assertRaises(c.Incomplete):c.media_drag_targets(bad,{c.PACKAGE})



class EvidenceBoundaryTests(unittest.TestCase):
    def test_snapshot_cannot_change_database_listing_or_media_identity(self):
        c.validate_snapshot(snapshot([photo(1)]), fixture())
        variants=[]
        for key,bad in [('nonce','e'*32),('app_env','uat'),('database','other'),
                        ('api_origin','https://remote.example'),('user_count',4),('property_count',2)]:
            value=snapshot();value[key]=bad;variants.append(value)
        value=snapshot();value['listing']['id']=999;variants.append(value)
        value=snapshot();value['listing']['title']='unrelated listing';variants.append(value)
        value=snapshot([photo(1),photo(1,1)]);variants.append(value)
        for key,bad in [('id',True),('sort_order',-1),('is_primary',1),('sha256','bad'),('relevance_status','auto-approved')]:
            value=snapshot([photo(1)]);value['listing']['images'][0][key]=bad;variants.append(value)
        for value in variants:
            with self.subTest(value=value),self.assertRaises(GateError):c.validate_snapshot(value,fixture())

    def test_add_remove_and_reopen_require_observed_persistent_change(self):
        empty=snapshot();added=snapshot([photo(1),photo(2,1),photo(3,2)])
        c.assert_transition('media_added',empty,added,fixture())
        reordered=snapshot([photo(2),photo(1,1),photo(3,2)])
        c.assert_transition('media_reordered',added,reordered,fixture())
        primary=snapshot([photo(1),photo(2,1),photo(3,2)])
        c.assert_transition('media_primary',reordered,primary,fixture())
        removed=snapshot([photo(2),photo(3,1)])
        c.assert_transition('media_removed',primary,removed,fixture())
        c.assert_transition('media_reopened',removed,deepcopy(removed),fixture())
        for name,before,after in [('media_added',empty,empty),('media_primary',added,added),
                                  ('media_added',empty,snapshot([photo(1),photo(2,1),photo(4,2)])),
                                  ('media_added',empty,snapshot([photo(2),photo(1,1),photo(3,2)])),
                                  ('media_removed',primary,primary),('media_reopened',removed,snapshot([photo(3),photo(2,1)]))]:
            with self.subTest(name=name),self.assertRaises(c.Incomplete):c.assert_transition(name,before,after,fixture())

    def test_bad_image_return_and_approval_cannot_be_inferred_from_submission(self):
        draft=snapshot([photo(2),photo(3,1)])
        submitted=snapshot([photo(2),photo(3,1)],review_status='submitted',
                           reviews=[review(1,'submitted','advertiser')])
        c.assert_transition('submitted',draft,submitted,fixture())
        rejected=snapshot([photo(2,relevance='relevant'),photo(3,1,relevance='unrelated')],review_status='under_review',
                          reviews=submitted['listing']['reviews'] + [review(2,'media_relevance_review',image_id=3,decision='unrelated')])
        c.assert_transition('bad_rejected',submitted,rejected,fixture())
        returned=deepcopy(rejected);returned['listing'].update(review_status='returned_for_correction',last_review_reason=c.REASON)
        returned['listing']['reviews'].append(review(3,'returned_for_correction'))
        c.assert_transition('returned',rejected,returned,fixture())
        replaced=snapshot([photo(2),photo(4,1)],review_status='returned_for_correction',last_review_reason=c.REASON,
                          reviews=deepcopy(returned['listing']['reviews']))
        c.assert_transition('replaced',returned,replaced,fixture())
        resubmitted=deepcopy(replaced);resubmitted['listing']['review_status']='submitted'
        resubmitted['listing']['reviews'].append(review(4,'submitted','advertiser'))
        c.assert_transition('resubmitted',replaced,resubmitted,fixture())
        approved=snapshot([photo(2,relevance='relevant'),photo(4,1,relevance='relevant')],status='published',review_status='approved',
                          reviews=resubmitted['listing']['reviews'] + [review(5,'approved')])
        c.assert_transition('approved',resubmitted,approved,fixture())
        for name,before,after in [('bad_rejected',submitted,submitted),('returned',rejected,dict(returned,listing={**returned['listing'],'last_review_reason':'unrelated reason'})),
                                  ('replaced',returned,returned),('approved',submitted,submitted),
                                  ('replaced',returned,snapshot([photo(2),photo(5,1)])),
                                  ('approved',submitted,snapshot([photo(2,relevance='relevant'),photo(4,1,relevance='unrelated')],status='published',review_status='approved'))]:
            with self.subTest(name=name),self.assertRaises(c.Incomplete):c.assert_transition(name,before,after,fixture())

    def test_decisions_require_a_fresh_review_by_the_correct_local_actor(self):
        draft=snapshot([photo(2),photo(3,1)])
        submitted=snapshot([photo(2),photo(3,1)],review_status='submitted',reviews=[review(1,'submitted','advertiser')])
        rejected=snapshot([photo(2,relevance='relevant'),photo(3,1,relevance='unrelated')],review_status='under_review',
                          reviews=[review(2,'media_relevance_review',image_id=3,decision='unrelated')])
        returned=deepcopy(rejected);returned['listing'].update(review_status='returned_for_correction',last_review_reason=c.REASON,
                                                               reviews=[review(3,'returned_for_correction')])
        replacement=snapshot([photo(2),photo(4,1)],review_status='returned_for_correction')
        resubmitted=snapshot([photo(2),photo(4,1)],review_status='submitted',reviews=[review(4,'submitted','advertiser')])
        approved=snapshot([photo(2,relevance='relevant'),photo(4,1,relevance='relevant')],status='published',review_status='approved',
                          reviews=[review(5,'approved')])
        for name,before,after in [('submitted',draft,submitted),('resubmitted',replacement,resubmitted),
                                  ('bad_rejected',submitted,rejected),('returned',rejected,returned),
                                  ('approved',resubmitted,approved),('reapproved',resubmitted,approved)]:
            c.assert_transition(name,before,after,fixture())
            for change in ('missing_review','missing_actor','wrong_actor','wrong_action','stale_review'):
                old,new=deepcopy(before),deepcopy(after)
                if change=='missing_review':new['listing']['reviews']=[]
                elif change=='missing_actor':del new['listing']['reviews'][-1]['actor_user_id']
                elif change=='wrong_actor':new['listing']['reviews'][-1]['actor_user_id']=fixture()['actors']['researcher']['id']
                elif change=='wrong_action':new['listing']['reviews'][-1]['action']='unreviewed_success'
                else:old['listing']['reviews']=deepcopy(new['listing']['reviews'])
                with self.subTest(name=name,change=change),self.assertRaises(GateError):
                    c.assert_transition(name,old,new,fixture())
        for metadata in ({},{'image_id':2,'decision':'unrelated'},{'image_id':3,'decision':'relevant'}):
            wrong=deepcopy(rejected);wrong['listing']['reviews'][-1]['metadata']=metadata
            with self.subTest(metadata=metadata),self.assertRaises(c.Incomplete):
                c.assert_transition('bad_rejected',submitted,wrong,fixture())

    def test_public_title_requires_both_server_result_and_actual_native_witness(self):
        approved=snapshot([photo(2,relevance='relevant'),photo(4,1,relevance='relevant')],status='published',review_status='approved')
        old=deepcopy(approved);old.update(public_title=fixture()['title'],native_title_seen=fixture()['title'])
        c.assert_transition('public_old',approved,old,fixture())
        new=deepcopy(approved);new['listing']['title']=fixture()['updated_title'];new.update(public_title=fixture()['updated_title'],native_title_seen=fixture()['updated_title'])
        c.assert_transition('public_new',old,new,fixture())
        for change in ({'native_title_seen':None},{'public_title':fixture()['title']},{'native_title_seen':fixture()['title']}):
            bad=deepcopy(new);bad.update(change)
            with self.subTest(change=change),self.assertRaises(c.Incomplete):c.assert_transition('public_new',old,bad,fixture())
        with self.assertRaises(c.Incomplete):c.assert_transition('public_new',approved,new,fixture())

    def test_pending_change_is_not_public_until_it_is_reviewed_again(self):
        old=snapshot([photo(2,relevance='relevant'),photo(4,1,relevance='relevant')],status='published',review_status='approved')
        pending=snapshot([photo(2,relevance='relevant'),photo(4,1,relevance='relevant')],title=fixture()['updated_title'],status='pending',review_status='submitted')
        pending['public_status']=404
        c.assert_transition('pending_edit',old,pending,fixture())
        for key,bad_value in [('title',fixture()['title']),('status','published'),('review_status','approved')]:
            bad=deepcopy(pending);bad['listing'][key]=bad_value
            with self.subTest(key=key),self.assertRaises(c.Incomplete):c.assert_transition('pending_edit',old,bad,fixture())
        for code in (200,403,500,None):
            bad=deepcopy(pending);bad['public_status']=code
            with self.subTest(code=code),self.assertRaises(c.Incomplete):c.assert_transition('pending_edit',old,bad,fixture())

    def test_unknown_transition_is_never_silently_accepted(self):
        with self.assertRaises(c.Incomplete):c.assert_transition('unreviewed_success',snapshot(),snapshot(),fixture())

    def test_transition_rejects_foreign_before_snapshot(self):
        before=snapshot();before['nonce']='e'*32
        with self.assertRaises(GateError):c.assert_transition('media_added',before,snapshot([photo(1),photo(2,1),photo(3,2)]),fixture())


if __name__ == '__main__':
    unittest.main()
