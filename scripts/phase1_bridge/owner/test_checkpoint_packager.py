"""Offline checkpoint tests: synthetic media and a generated test certificate only."""
from copy import deepcopy
import hashlib
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import uuid
import zipfile

from PIL import Image

import checkpoint_packager as pack


@unittest.skipUnless(shutil.which('openssl'), 'OpenSSL required for actual CMS boundary tests')
class CheckpointTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cert_temp = tempfile.TemporaryDirectory()
        cls.cert_root = Path(cls.cert_temp.name)
        cls.certificate = cls.cert_root / 'test-recipient.pem'
        cls.private_key = cls.cert_root / 'test-private.pem'
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
            '-keyout', str(cls.private_key), '-out', str(cls.certificate), '-days', '1',
            '-subj', '/CN=OfflineCheckpointTestOnly'], check=True, capture_output=True)
        cls.private_key.chmod(0o600)
        cls.certificate_sha = hashlib.sha256(cls.certificate.read_bytes()).hexdigest()

    @classmethod
    def tearDownClass(cls): cls.cert_temp.cleanup()

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(); self.addCleanup(self.temporary.cleanup)
        self.folder = Path(self.temporary.name)
        self.owner = self.folder / 'owner'; self.owner.mkdir(mode=0o700)
        self.evidence = self.folder / 'evidence'; self.evidence.mkdir(mode=0o700)
        self.identity = {'repo': pack.REPO, 'run_id': '9001', 'run_attempt': 2,
                         'source_sha': 'a' * 40, 'toolbundle_sha': 'b' * 64}
        self.fixture = {'draft_uuid': str(uuid.uuid4()), 'tag': 'AQER-C1-258147abcdef',
                        'actor_id': 28, 'property_id': None}
        self.baseline = {'properties': {'count': 25, 'sha256': 'c' * 64},
                         'drafts': {'count': 7, 'sha256': 'd' * 64}}
        self.stage = {'context': 'C1_REVIEW', 'postconditions': {'same_fixture_held': True},
                      'report_scope': 'OFFLINE_SYNTHETIC_TEST_ONLY'}
        self.alias = 'PRIVATE_SYNTHETIC_ALIAS_SENTINEL'
        self.writer = self.make_writer(); self.addCleanup(self.writer.close)

    def make_writer(self, **changes):
        kwargs = dict(root=self.owner, evidence_root=self.evidence, identity=self.identity,
                      recipient_cert=self.certificate, recipient_sha256=self.certificate_sha,
                      job_public=bytes(range(32)), root_key_id='e' * 64,
                      private_aliases=(self.alias,))
        kwargs.update(changes)
        return pack.CheckpointPackager(**kwargs)

    def seal(self, *, seq=0, kind='fixture_checkpoint', evidence=None, fixture=None,
             baseline=None, stage=None, **changes):
        args = dict(seq=seq, kind=kind, phase='C1',
                    cursor='PRE_NATIVE_EDIT_AFTER_TITLE_BOOTSTRAP' if kind == 'fixture_checkpoint' else 'C1_REVIEW',
                    fixture=self.fixture if fixture is None else fixture,
                    baseline=self.baseline if baseline is None else baseline,
                    stage=self.stage if stage is None else stage,
                    evidence=[] if evidence is None else evidence, prev_result_sha='0' * 64,
                    created_utc='2026-11-04T01:02:03Z')
        args.update(changes)
        return self.writer.seal(**args)

    def png(self, name='C1-restored.png', size=(540, 960)):
        path = self.evidence / name
        Image.new('RGB', size, (32, 112, 144)).save(path)
        path.chmod(0o600)
        return {'file': name, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
                'kind': 'png', 'capture': 'official_emulator_console_png'}

    def decrypt(self, sealed):
        output = self.folder / ('decrypted-' + sealed.directory.name + '.zip')
        subprocess.run(['openssl', 'cms', '-decrypt', '-binary', '-inform', 'DER',
            '-in', str(sealed.directory / 'checkpoint.cms'), '-recip', str(self.certificate),
            '-inkey', str(self.private_key), '-out', str(output)], check=True, capture_output=True)
        return zipfile.ZipFile(output)

    def test_actual_host_png_marker_is_preserved_without_relabeling(self):
        self.seal()
        frame = self.png()
        frame['capture'] = 'official_emulator_console_host_png'
        sealed = self.seal(seq=1, kind='review_checkpoint', evidence=[frame])
        with self.decrypt(sealed) as archive:
            value = json.loads(archive.read('CHECKPOINT.json'))
        self.assertEqual(value['frames'][0]['capture'], 'official_emulator_console_host_png')

    def test_actual_premutation_CMS_contains_only_minimized_fixture_and_baseline(self):
        sealed = self.seal()
        public = sealed.public_receipt
        self.assertIsNone(sealed.held_context)
        self.assertEqual(public['seq'], 0); self.assertIs(public['phase1_accepted'], False)
        self.assertEqual(public['cursor'], 'PRE_NATIVE_EDIT_AFTER_TITLE_BOOTSTRAP')
        self.assertEqual(set(public), {'version', 'repo', 'run_id', 'run_attempt', 'source_sha',
            'toolbundle_sha', 'seq', 'kind', 'phase', 'cursor', 'checkpoint_challenge',
            'prev_result_sha', 'cipher_sha', 'cipher_bytes', 'created_utc', 'phase1_accepted'})
        text = json.dumps(public)
        for private in [self.fixture['draft_uuid'], self.fixture['tag'], self.alias]:
            self.assertNotIn(private, text)
        ciphertext = (sealed.directory / 'checkpoint.cms').read_bytes()
        self.assertEqual(hashlib.sha256(ciphertext).hexdigest(), public['cipher_sha'])
        self.assertEqual(len(ciphertext), public['cipher_bytes'])
        self.assertNotIn(self.fixture['draft_uuid'].encode(), ciphertext)
        with self.decrypt(sealed) as archive:
            self.assertEqual(archive.namelist(), ['CHECKPOINT.json'])
            private = json.loads(archive.read('CHECKPOINT.json'))
        self.assertEqual(private['fixture'], self.fixture)
        self.assertEqual(private['baseline'], self.baseline)
        self.assertEqual(private['checkpoint'], {name: value for name, value in public.items()
                         if name not in {'cipher_sha', 'cipher_bytes'}})
        self.assertIsNone(private['context_without_cipher'])
        self.assertEqual(private['frames'], [])
        self.assertNotIn('private', private['job_public_b64'].lower())
        self.assertEqual(list((self.owner / '.checkpoint-staging').iterdir()), [])
        self.assertEqual({path.name for path in sealed.directory.iterdir()},
                         {'checkpoint.cms', 'PUBLIC_RECEIPT.json'})
        for path in sealed.directory.iterdir():
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            self.assertEqual(path.stat().st_nlink, 1)

    def test_review_context_adds_actual_outer_hash_without_self_hash_circularity(self):
        self.seal()
        frame = self.png()
        sealed = self.seal(seq=1, kind='review_checkpoint', evidence=[frame])
        self.assertEqual(sealed.held_context['cipher_sha'], sealed.public_receipt['cipher_sha'])
        with self.decrypt(sealed) as archive:
            self.assertEqual(set(archive.namelist()), {'CHECKPOINT.json', frame['file']})
            actual = json.loads(archive.read('CHECKPOINT.json'))
            self.assertEqual(hashlib.sha256(archive.read(frame['file'])).hexdigest(), frame['sha256'])
        without = actual['context_without_cipher']
        self.assertNotIn('cipher_sha', without)
        self.assertEqual(dict(without, cipher_sha=sealed.public_receipt['cipher_sha']), sealed.held_context)
        self.assertEqual(actual['frames'][0]['width'], 540)
        self.assertEqual(actual['frames'][0]['height'], 960)
        self.assertEqual(actual['checkpoint'], {name: value for name, value in sealed.public_receipt.items()
                         if name not in {'cipher_sha', 'cipher_bytes'}})
        self.assertNotIn('manual_review_completed', actual)
        self.assertNotIn('accepted', actual)

    def test_sequence_is_immutable_and_a_gap_or_boolean_is_refused(self):
        first = self.seal()
        before = (first.directory / 'checkpoint.cms').read_bytes()
        for seq in [0, 2, True]:
            with self.subTest(seq=seq), self.assertRaises(pack.PackagerRefused):
                self.seal(seq=seq, kind='review_checkpoint')
        self.assertEqual((first.directory / 'checkpoint.cms').read_bytes(), before)

    def test_first_nonfixture_checkpoint_cannot_be_a_review(self):
        with self.assertRaises(pack.PackagerRefused):
            self.seal(seq=1, kind='review_checkpoint')
        self.assertEqual(self.writer.max_allocated, -1)

    def test_terminal_before_bootstrap_can_report_no_fixture_without_faking_one(self):
        terminal = self.writer.seal(seq=1, kind='terminal_checkpoint', phase='C5',
            cursor='SETUP_FAILED', fixture=None, baseline=None,
            stage={'postconditions': {'fixture_created': False}}, evidence=[],
            prev_result_sha='0' * 64, created_utc='2026-11-04T01:02:03Z')
        with self.decrypt(terminal) as archive:
            value = json.loads(archive.read('CHECKPOINT.json'))
        self.assertIsNone(value['fixture']); self.assertIsNone(value['baseline'])
        self.assertIsNone(terminal.held_context)
        self.assertEqual(value['checkpoint'], {name: item for name, item in terminal.public_receipt.items()
                         if name not in {'cipher_sha', 'cipher_bytes'}})

    def test_fixture_checkpoint_requires_unpromoted_identity_and_no_media(self):
        promoted = dict(self.fixture, property_id=77)
        for kwargs in [{'fixture': promoted}, {'evidence': [self.png()]}]:
            with self.subTest(kind=list(kwargs)), self.assertRaises(pack.PackagerRefused):
                self.seal(**kwargs)
        with self.assertRaisesRegex(pack.PackagerRefused, 'explicit_post_bootstrap_checkpoint_scope'):
            self.seal(cursor='PRE_ALL_MUTATIONS')

    def test_full_state_original_rows_and_credentials_are_not_minimal_metadata(self):
        for change in [{'fixture': dict(self.fixture, payload={'title': 'old work'})},
                       {'baseline': dict(self.baseline, original_rows=[{'id': 1}])},
                       {'stage': {'state': {'original_rows': []}}},
                       {'stage': {'bindings': {'otp': 'invented'}}},
                       {'stage': {'postconditions': {'access_token': 'invented'}}},
                       {'stage': {'report_scope': self.alias}},
                       {'stage': {'bindings': {'note': '+999999999999'}}},
                       {'stage': {'postconditions': {'phase1_accepted': True}}},
                       {'stage': {'executor_cursor': 1.5}}]:
            with self.subTest(kind=list(change)), self.assertRaises(pack.PackagerRefused) as error:
                self.seal(**change)
            self.assertNotIn(self.alias, str(error.exception))
        self.assertEqual(self.writer.max_allocated, -1)

    def test_fixture_uuid_tag_baseline_and_pinned_property_cannot_drift(self):
        self.seal()
        for change in [{'fixture': dict(self.fixture, draft_uuid=str(uuid.uuid4()))},
                       {'fixture': dict(self.fixture, tag='AQER-C1-abcdef258147')},
                       {'baseline': dict(self.baseline, properties={'count': 24, 'sha256': 'c' * 64})}]:
            with self.subTest(kind=list(change)), self.assertRaisesRegex(pack.PackagerRefused, 'same_fixture_and_baseline'):
                self.seal(seq=1, kind='review_checkpoint', **change)
        promoted = dict(self.fixture, property_id=77)
        self.seal(seq=1, kind='review_checkpoint', fixture=promoted)
        with self.assertRaisesRegex(pack.PackagerRefused, 'same_pinned_property'):
            self.seal(seq=2, kind='review_checkpoint', fixture=dict(promoted, property_id=78))

    def test_symlink_hardlink_broad_mode_and_unknown_media_type_are_refused(self):
        self.seal(); frame = self.png()
        target = self.evidence / frame['file']
        original = self.evidence / 'outside.png'
        target.rename(original)
        for kind in ['symlink', 'hardlink', 'broad']:
            with self.subTest(kind=kind):
                if kind == 'symlink': target.symlink_to(original)
                elif kind == 'hardlink': os.link(original, target)
                else: shutil.copyfile(original, target); target.chmod(0o644)
                with self.assertRaises(pack.PackagerRefused):
                    self.seal(seq=1, kind='review_checkpoint', evidence=[frame])
                target.unlink()
        for entry in [dict(frame, file='../outside.png'), dict(frame, kind=[]),
                      dict(frame, capture='pretend_host_webm'), dict(frame, sha256='f' * 64)]:
            with self.subTest(kind='invalid_manifest'), self.assertRaises(pack.PackagerRefused):
                self.seal(seq=1, kind='review_checkpoint', evidence=[entry])

    def test_actual_dimensions_invalid_png_and_plaintext_video_are_refused(self):
        self.seal()
        bad_size = self.png('C1-small.png', (10, 10))
        fake_png = self.evidence / 'C1-fake.png'; fake_png.write_bytes(b'not a screenshot'); fake_png.chmod(0o600)
        fake_video = self.evidence / 'C1-fake.webm'; fake_video.write_bytes(b'PRIVATE_SYNTHETIC_VIDEO_SENTINEL'); fake_video.chmod(0o600)
        entries = [bad_size,
            {'file': fake_png.name, 'sha256': hashlib.sha256(fake_png.read_bytes()).hexdigest(),
             'kind': 'png', 'capture': 'official_emulator_console_png'},
            {'file': fake_video.name, 'sha256': hashlib.sha256(fake_video.read_bytes()).hexdigest(),
             'kind': 'webm', 'capture': 'official_emulator_console_host_webm'}]
        for entry in entries:
            with self.subTest(file=entry['file']), self.assertRaises(pack.PackagerRefused) as error:
                self.seal(seq=1, kind='review_checkpoint', evidence=[entry])
            self.assertNotIn('PRIVATE_SYNTHETIC_VIDEO_SENTINEL', str(error.exception))

    def test_encryption_failure_removes_plaintext_and_consumes_allocated_sequence(self):
        with patch.object(pack.subprocess, 'run', side_effect=subprocess.TimeoutExpired(['fixed-cms-test'], 60)):
            with self.assertRaisesRegex(pack.PackagerRefused, 'checkpoint_packaging_failed'):
                self.seal()
        self.assertEqual(self.writer.max_allocated, 0)
        self.assertEqual(list((self.owner / '.checkpoint-staging').iterdir()), [])
        self.assertFalse((self.owner / 'checkpoints/000000/PUBLIC_RECEIPT.json').exists())
        with self.assertRaisesRegex(pack.PackagerRefused, 'fresh_checkpoint_sequence'):
            self.seal()
        terminal = self.seal(seq=1, kind='terminal_checkpoint')
        self.assertEqual(terminal.public_receipt['seq'], 1)

    def test_pinned_recipient_and_private_owned_roots_are_mandatory(self):
        for change in [{'recipient_sha256': 'f' * 64}, {'private_aliases': ()}]:
            extra = self.folder / ('extra-' + str(len(list(self.folder.iterdir())))); extra.mkdir(mode=0o700)
            with self.subTest(kind=list(change)), self.assertRaises(pack.PackagerRefused):
                self.make_writer(root=extra, **change)
        linked = self.folder / 'alias'; linked.symlink_to(self.owner, target_is_directory=True)
        with self.assertRaises(pack.PackagerRefused): self.make_writer(root=linked)

    def test_closed_packager_does_not_write_relative_to_current_directory(self):
        self.writer.close()
        with self.assertRaisesRegex(pack.PackagerRefused, 'packager_closed'):
            self.seal()

    def test_identity_property_returns_a_fresh_readonly_property_copy(self):
        original = dict(self.identity)
        exposed = self.writer.identity
        exposed['run_id'] = '9002'
        self.identity['source_sha'] = 'f' * 40
        self.assertEqual(self.writer.identity, original)
        self.assertIsNot(self.writer.identity, self.writer.identity)
        with self.assertRaises(AttributeError):
            self.writer.identity = exposed
        self.assertEqual(self.seal().public_receipt['source_sha'], original['source_sha'])

    @unittest.skipUnless(shutil.which('ffmpeg') and shutil.which('ffprobe'), 'Video tools unavailable')
    def test_actual_host_WebM_preserves_exact_fractional_ffprobe_duration_text(self):
        self.seal()
        video = self.evidence / 'C4-restored.webm'
        subprocess.run(['ffmpeg', '-v', 'error', '-f', 'lavfi', '-i',
            'color=c=blue:s=540x960:r=24', '-frames:v', '3', '-an', '-c:v', 'libvpx-vp9',
            '-y', str(video)], check=True, capture_output=True, timeout=20)
        video.chmod(0o600)
        actual = json.loads(subprocess.run(['ffprobe', '-v', 'error', '-show_entries',
            'format=duration', '-of', 'json', str(video)], check=True, capture_output=True).stdout)['format']['duration']
        self.assertIn('.', actual)
        evidence = {'file': video.name, 'sha256': hashlib.sha256(video.read_bytes()).hexdigest(),
                    'kind': 'webm', 'capture': 'official_emulator_console_host_webm'}
        sealed = self.seal(seq=1, kind='review_checkpoint', evidence=[evidence])
        with self.decrypt(sealed) as archive:
            frame = json.loads(archive.read('CHECKPOINT.json'))['frames'][0]
        self.assertIs(type(frame['duration_decimal']), str)
        self.assertEqual(frame['duration_decimal'], actual)
        self.assertEqual(frame['capture'], 'official_emulator_console_host_webm')

    def test_media_and_cipher_size_bounds_prevent_a_public_receipt(self):
        frame = self.png()
        self.seal()
        with patch.object(pack, 'MAX_MEDIA', 32):
            with self.assertRaises(pack.PackagerRefused):
                self.seal(seq=1, kind='review_checkpoint', evidence=[frame])
        self.assertEqual(self.writer.max_allocated, 0)
        with patch.object(pack, 'MAX_CIPHER', 10):
            with self.assertRaises(pack.PackagerRefused):
                self.seal(seq=1, kind='review_checkpoint')
        self.assertEqual(self.writer.max_allocated, 1)
        self.assertFalse((self.owner / 'checkpoints/000001/PUBLIC_RECEIPT.json').exists())
        self.assertEqual(list((self.owner / '.checkpoint-staging').iterdir()), [])

    @unittest.skipUnless(shutil.which('ffmpeg') and shutil.which('ffprobe'),'Video tools unavailable')
    def test_native_Vorbis_is_silent_and_original_WebM_bytes_are_preserved(self):
        self.seal();video=self.evidence/'C1-native-silent.webm'
        subprocess.run(['ffmpeg','-nostdin','-v','error','-f','lavfi','-i','color=c=blue:s=540x960:r=10',
            '-f','lavfi','-i','anullsrc=r=44100:cl=stereo','-t','0.3','-c:v','libvpx-vp9','-c:a','libvorbis',
            '-y',str(video)],check=True,capture_output=True,timeout=25)
        video.chmod(0o600);original=video.read_bytes()
        evidence={'file':video.name,'sha256':hashlib.sha256(original).hexdigest(),'kind':'webm',
                  'capture':'official_emulator_console_host_webm'}
        sealed=self.seal(seq=1,kind='review_checkpoint',evidence=[evidence])
        with self.decrypt(sealed) as archive:
            self.assertEqual(archive.read(video.name),original)
        self.assertEqual(video.read_bytes(),original)

    @unittest.skipUnless(shutil.which('ffmpeg') and shutil.which('ffprobe'),'Video tools unavailable')
    def test_audible_native_audio_is_refused_without_publishing_checkpoint(self):
        self.seal();video=self.evidence/'C1-native-audible.webm'
        subprocess.run(['ffmpeg','-nostdin','-v','error','-f','lavfi','-i','color=c=blue:s=540x960:r=10',
            '-f','lavfi','-i','sine=frequency=1000:sample_rate=44100','-t','0.3','-c:v','libvpx-vp9',
            '-c:a','libvorbis','-y',str(video)],check=True,capture_output=True,timeout=25)
        video.chmod(0o600);original=video.read_bytes()
        evidence={'file':video.name,'sha256':hashlib.sha256(original).hexdigest(),'kind':'webm',
                  'capture':'official_emulator_console_host_webm'}
        with self.assertRaisesRegex(pack.PackagerRefused,'native_audio_exact_silence_required'):
            self.seal(seq=1,kind='review_checkpoint',evidence=[evidence])
        self.assertEqual(video.read_bytes(),original)
        self.assertFalse((self.owner/'checkpoints/000001/PUBLIC_RECEIPT.json').exists())

    def test_duplicate_media_is_not_archived_twice(self):
        self.seal(); frame = self.png()
        with self.assertRaisesRegex(pack.PackagerRefused, 'duplicate_or_total'):
            self.seal(seq=1, kind='review_checkpoint', evidence=[frame, frame])
        self.assertEqual(self.writer.max_allocated, 0)


if __name__ == '__main__': unittest.main()
