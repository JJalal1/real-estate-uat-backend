import importlib.util
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
import prepare_phase1_native_account as build


class NativeAccountBuildSafetyTest(unittest.TestCase):
    def test_optional_installer_refuses_changed_build_identity_before_export(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary); evidence, export = self.export_context(folder)
            private = folder / 'private'; private.mkdir()
            (private / 'target.apk').write_bytes(b'INVENTED_NOT_INSTALLABLE_TEST_ONLY')
            (private / 'APK_VERIFICATION.json').write_text(json.dumps({'source_commit': 'b' * 40}))
            proof = {'source_commit': 'a' * 40, 'ci_run_id': '123', 'version_code': 1467}
            with patch.object(build, 'guard', return_value=proof), patch.object(build, 'PRIVATE', private), \
                    patch.object(build, 'EVIDENCE', evidence), patch.object(build, 'EXPORT', export):
                with self.assertRaisesRegex(RuntimeError, 'installer_identity'):
                    build.encrypt_evidence({'RUNNER_TEMP': str(folder)}, include_installer=True)
            self.assertFalse(export.exists())

    @unittest.skipUnless(shutil.which('openssl'), 'OpenSSL unavailable')
    def test_optional_installer_and_host_clip_leave_only_matching_ciphertext(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary); evidence, export = self.export_context(folder)
            # Invented non-installable bytes test encryption, not APK validation.
            private = folder / 'private'; private.mkdir()
            apk = b'OFFLINE_INVENTED_APK_BYTES_NOT_INSTALLABLE'
            (private / 'target.apk').write_bytes(apk)
            (evidence / 'C1_test.webm').write_bytes(b'OFFLINE_TEST_MEDIA_NOT_A_NATIVE_CAPTURE')
            proof = {'source_commit': 'a' * 40, 'ci_run_id': '123', 'ci_run_number': 1, 'version_code': 1467}
            identity = {**proof, 'package': 'com.aqer.yemen.uat', 'bytes': len(apk),
                        'sha256': hashlib.sha256(apk).hexdigest()}
            (private / 'APK_VERIFICATION.json').write_text(json.dumps(identity))
            key, certificate = folder / 'key.pem', folder / 'recipient.pem'
            subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
                            '-keyout', str(key), '-out', str(certificate), '-days', '1',
                            '-subj', '/CN=OfflineInstallerCipherTest'], check=True, capture_output=True)
            key.chmod(0o600)
            with patch.object(build, 'guard', return_value=proof), patch.object(build, 'PRIVATE', private), \
                    patch.object(build, 'EVIDENCE', evidence), patch.object(build, 'EXPORT', export), \
                    patch.object(build.close, 'RECIPIENT', str(certificate)):
                build.encrypt_evidence({'RUNNER_TEMP': str(folder)}, include_installer=True)
            self.assertEqual({p.name for p in export.iterdir()}, {'evidence.cms', 'installer.cms', 'PUBLIC_RECEIPT.json'})
            receipt = json.loads((export / 'PUBLIC_RECEIPT.json').read_text())
            self.assertFalse(receipt['phase1_accepted'])
            self.assertEqual(receipt['installer_identity']['sha256'], identity['sha256'])
            self.assertNotIn(apk.decode(), json.dumps(receipt))
            for name in ('evidence', 'installer'):
                subprocess.run(['openssl', 'cms', '-decrypt', '-binary', '-inform', 'DER',
                    '-in', str(export / (name + '.cms')), '-recip', str(certificate),
                    '-inkey', str(key), '-out', str(folder / (name + '-plain'))], check=True, capture_output=True)
            self.assertEqual((folder / 'installer-plain').read_bytes(), apk)
            with zipfile.ZipFile(folder / 'evidence-plain') as archive:
                self.assertIsNone(archive.testzip())
                self.assertEqual(set(archive.namelist()), {'report.json', 'C1_test.webm'})

    def environment(self):
        return {'GITHUB_ACTIONS': 'true', 'GITHUB_REPOSITORY': 'JJalal1/real-estate-uat-backend',
                'GITHUB_REF': build.REF, 'GITHUB_EVENT_NAME': 'push',
                'AQER_PHASE1_NATIVE_ACCOUNT': 'true', 'GITHUB_SHA': 'a' * 40,
                'SOURCE_COMMIT': 'a' * 40, 'GITHUB_RUN_ID': '123', 'GITHUB_RUN_NUMBER': '1'}

    def fake_git(self, changed=None, wrong_component=None):
        def text(argv):
            if argv == ['git', 'rev-parse', 'HEAD']:
                return 'a' * 40
            if argv[:3] == ['git', 'diff', '--name-only']:
                return changed if changed is not None else 'scripts/probe_phase1_native_account.py'
            if argv[:2] == ['git', 'rev-parse']:
                component = argv[-1].split(':')[-1]
                if component == wrong_component:
                    return 'b' * 40
                return {'mobile_app': build.MOBILE_TREE, 'backend-api-runtime': build.BACKEND_TREE}[component]
            return ''
        return text

    def test_source_guard_rejects_product_or_unreviewed_scope_changes(self):
        for kwargs, message in [({'changed': 'mobile_app/lib/main.dart'}, 'scope'),
                                ({'wrong_component': 'mobile_app'}, 'component'),
                                ({'wrong_component': 'backend-api-runtime'}, 'component')]:
            with self.subTest(kwargs=kwargs), patch.object(build, 'text', self.fake_git(**kwargs)):
                with self.assertRaisesRegex(RuntimeError, message):
                    build.guard(self.environment())

    def test_context_guard_rejects_other_branch_or_mismatched_source(self):
        for replacement in [{'GITHUB_REF': 'refs/heads/main'}, {'SOURCE_COMMIT': 'b' * 40},
                            {'GITHUB_ACTIONS': 'false'}, {'GITHUB_EVENT_NAME': 'pull_request'},
                            {'GITHUB_RUN_NUMBER': '0'}, {'GITHUB_RUN_NUMBER': '-1'},
                            {'GITHUB_RUN_NUMBER': 'not-a-number'}, {'GITHUB_RUN_NUMBER': ''}]:
            with self.subTest(replacement=replacement):
                with self.assertRaisesRegex(RuntimeError, 'context'):
                    build.guard(dict(self.environment(), **replacement))

    def test_version_uses_the_positive_workflow_run_number(self):
        with patch.object(build, 'text', self.fake_git()), \
             patch.object(build, 'digest', return_value=build.close.RECIPIENT_SHA256), \
             patch.object(build, 'run'):
            first = build.guard(self.environment())
            later = build.guard(dict(self.environment(), GITHUB_RUN_NUMBER='7'))
        self.assertEqual(first['version_code'], 1467)
        self.assertEqual(later['version_code'], 1473)
        self.assertEqual(later['ci_run_number'], 7)

    def export_context(self, folder):
        evidence = folder / 'evidence'; evidence.mkdir()
        (evidence / 'report.json').write_text('{"scope":"test-only"}\n')
        return evidence, folder / 'export'

    def test_export_rejects_raw_tree_secrets_and_symlinks(self):
        for filename in ['tree.json', 'session.env', 'private-key.pem', '../escape.png']:
            with self.subTest(filename=filename), tempfile.TemporaryDirectory() as temporary:
                folder = Path(temporary); evidence, export = self.export_context(folder)
                if filename.startswith('../'):
                    secret = folder / 'outside'; secret.write_text('sentinel')
                    (evidence / 'linked.png').symlink_to(secret)
                else:
                    (evidence / filename).write_text('sentinel')
                with patch.object(build, 'guard', return_value={}), \
                     patch.object(build, 'EVIDENCE', evidence), patch.object(build, 'EXPORT', export):
                    with self.assertRaisesRegex(RuntimeError, 'allowlist'):
                        build.encrypt_evidence({'RUNNER_TEMP': str(folder)})
                self.assertFalse(export.exists())

    @unittest.skipUnless(shutil.which('openssl'), 'OpenSSL unavailable')
    def test_export_encrypts_the_whole_private_evidence_and_only_emits_safe_identity(self):
        with tempfile.TemporaryDirectory() as temporary:
            folder = Path(temporary); evidence, export = self.export_context(folder)
            sentinel = 'PRIVATE_NATIVE_CASE_SENTINEL'
            (evidence / 'report.json').write_text(json.dumps({'private_test_case': sentinel}))
            (evidence / 'C1_restored.png').write_bytes(b'not-a-real-frame-test-only')
            key = folder / 'key.pem'; certificate = folder / 'recipient.pem'
            subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
                            '-keyout', str(key), '-out', str(certificate), '-days', '1',
                            '-subj', '/CN=NativeEvidenceTestOnly'], check=True, capture_output=True)
            key.chmod(0o600)
            with patch.object(build, 'guard', return_value={'source_commit': 'a' * 40, 'ci_run_id': '123', 'ci_run_number': 1, 'version_code': 1467}), \
                 patch.object(build, 'EVIDENCE', evidence), patch.object(build, 'EXPORT', export), \
                 patch.object(build.close, 'RECIPIENT', str(certificate)):
                build.encrypt_evidence({'RUNNER_TEMP': str(folder)})
            self.assertEqual({p.name for p in export.iterdir()}, {'evidence.cms', 'PUBLIC_RECEIPT.json'})
            public = (export / 'PUBLIC_RECEIPT.json').read_text()
            self.assertNotIn(sentinel, public)
            self.assertFalse(json.loads(public)['phase1_accepted'])
            decrypted = folder / 'decrypted.zip'
            subprocess.run(['openssl', 'cms', '-decrypt', '-binary', '-inform', 'DER',
                            '-in', str(export / 'evidence.cms'), '-recip', str(certificate),
                            '-inkey', str(key), '-out', str(decrypted)], check=True, capture_output=True)
            with zipfile.ZipFile(decrypted) as archive:
                self.assertIsNone(archive.testzip())
                self.assertEqual(set(archive.namelist()), {'report.json', 'C1_restored.png'})
                self.assertIn(sentinel, archive.read('report.json').decode())


if __name__ == '__main__':
    unittest.main()
