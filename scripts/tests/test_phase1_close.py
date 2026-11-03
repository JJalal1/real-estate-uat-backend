import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest import mock

SCRIPTS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS))
spec = importlib.util.spec_from_file_location('phase1_close_under_test', SCRIPTS / 'prepare_phase1_close.py')
close = importlib.util.module_from_spec(spec)
spec.loader.exec_module(close)


class Phase1CloseSafetyTest(unittest.TestCase):
    def environment(self):
        return {'GITHUB_REPOSITORY': 'JJalal1/real-estate-uat-backend',
                'GITHUB_REF': close.REF, 'GITHUB_EVENT_NAME': 'push',
                'AQER_PHASE1_CLOSE': 'true', 'GITHUB_SHA': 'a' * 40,
                'SOURCE_COMMIT': 'a' * 40, 'GITHUB_RUN_ID': '123',
                'GITHUB_RUN_NUMBER': '1'}

    def test_guard_rejects_wrong_context_before_any_build(self):
        self.assertEqual(close.guard(self.environment()), 1465)
        replacements = {'GITHUB_REPOSITORY': 'other/repository', 'GITHUB_REF': 'refs/heads/main',
                        'GITHUB_EVENT_NAME': 'workflow_dispatch', 'AQER_PHASE1_CLOSE': 'false',
                        'GITHUB_SHA': 'not-a-commit', 'SOURCE_COMMIT': 'b' * 40,
                        'GITHUB_RUN_ID': '0', 'GITHUB_RUN_NUMBER': '-1'}
        for key, value in replacements.items():
            with self.subTest(key=key), self.assertRaises(RuntimeError):
                close.guard(self.environment() | {key: value})

    def test_source_rejects_unapproved_changed_paths_and_mobile_tree(self):
        def output(command):
            if command == ['git', 'rev-parse', 'HEAD']:
                return 'a' * 40
            if command[:3] == ['git', 'diff', '--name-only']:
                return 'backend-api-runtime/database/migrations/not-allowed.php'
            return ''
        with mock.patch.object(close, 'text_run', side_effect=output):
            with self.assertRaisesRegex(RuntimeError, 'task_source_scope_mismatch'):
                close.source_receipt(self.environment())

        def changed_mobile(command):
            if command == ['git', 'rev-parse', 'HEAD']:
                return 'a' * 40
            if command[:3] == ['git', 'diff', '--name-only']:
                return 'scripts/prepare_phase1_close.py'
            if command == ['git', 'rev-parse', 'HEAD:mobile_app']:
                return 'b' * 40
            return ''
        with mock.patch.object(close, 'text_run', side_effect=changed_mobile):
            with self.assertRaisesRegex(RuntimeError, 'mobile_component_changed'):
                close.source_receipt(self.environment())

    def test_recipient_bytes_must_match_the_pinned_current_certificate(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            recipient = root / close.RECIPIENT
            recipient.parent.mkdir()
            recipient.write_text('-----BEGIN CERTIFICATE-----\nwrong recipient\n')
            def output(command):
                if command == ['git', 'rev-parse', 'HEAD']:
                    return 'a' * 40
                if command[:3] == ['git', 'diff', '--name-only']:
                    return 'scripts/prepare_phase1_close.py'
                if command[1] == 'rev-parse':
                    return close.MOBILE_TREE
                return ''
            with mock.patch.object(close, 'ROOT', root), mock.patch.object(close, 'text_run', side_effect=output):
                with self.assertRaisesRegex(RuntimeError, 'current_recipient_mismatch'):
                    close.source_receipt(self.environment())

    def control_case(self, xml):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        originals = {}
        for name in close.CONTROL_SERVICES:
            path = root / name
            path.parent.mkdir(parents=True, exist_ok=True)
            originals[name] = ('candidate ' + name).encode()
            path.write_bytes(originals[name])
        def fake_run(command, **kwargs):
            self.assertEqual(command[:3], ['git', 'show', close.BASE + ':' + command[2].split(':', 1)[1]])
            return subprocess.CompletedProcess(command, 0, b'old source')
        def fake_php(command, **kwargs):
            self.assertEqual(command[:3], ['php', 'artisan', 'test'])
            junit = next(v.partition('=')[2] for v in command if v.startswith('--log-junit='))
            Path(junit).write_text(xml)
            for name in close.CONTROL_SERVICES:
                self.assertEqual((root / name).read_bytes(), b'old source')
            return subprocess.CompletedProcess(command, 1, '', '')
        contexts = [mock.patch.object(close, 'ROOT', root),
                    mock.patch.object(close, 'source_receipt', return_value={'source_commit': 'a' * 40}),
                    mock.patch.object(close, 'run', side_effect=fake_run),
                    mock.patch.object(close.subprocess, 'run', side_effect=fake_php),
                    mock.patch.dict(close.os.environ, {'RUNNER_TEMP': str(root)})]
        return root, originals, contexts

    def test_red_control_requires_the_specific_assertion_and_restores_candidate(self):
        xml = '<testsuites><testsuite><testcase name="' + close.RED_METHOD + '"><failure>' + close.RED_WITNESS + '</failure></testcase></testsuite></testsuites>'
        root, originals, contexts = self.control_case(xml)
        from contextlib import ExitStack
        with ExitStack() as stack:
            for context in contexts:
                stack.enter_context(context)
            close.red_control(self.environment())
        for name, content in originals.items():
            self.assertEqual((root / name).read_bytes(), content)
        result = json.loads((root / 'phase1-close-regression/RED_CONTROL.json').read_text())
        self.assertTrue(result['unit_number_failure_witnessed'])
        self.assertTrue(result['candidate_source_restored'])

    def test_red_control_rejects_an_unidentified_assertion_and_still_restores(self):
        for failure in ['Failed asserting that true is false.', 'An unrelated unit_number assertion']:
            with self.subTest(failure=failure):
                xml = '<testsuites><testsuite><testcase name="' + close.RED_METHOD + '"><failure>' + failure + '</failure></testcase></testsuite></testsuites>'
                root, originals, contexts = self.control_case(xml)
                from contextlib import ExitStack
                with ExitStack() as stack:
                    for context in contexts:
                        stack.enter_context(context)
                    with self.assertRaisesRegex(RuntimeError, 'did_not_witness_unit_proposal'):
                        close.red_control(self.environment())
                for name, content in originals.items():
                    self.assertEqual((root / name).read_bytes(), content)
                self.assertFalse((root / 'phase1-close-regression/RED_CONTROL.json').exists())

    def test_red_control_rejects_unrelated_runtime_errors_and_still_restores(self):
        xml = '<testsuites><testsuite><testcase name="' + close.RED_METHOD + '"><error>class missing</error></testcase></testsuite></testsuites>'
        root, originals, contexts = self.control_case(xml)
        from contextlib import ExitStack
        with ExitStack() as stack:
            for context in contexts:
                stack.enter_context(context)
            with self.assertRaisesRegex(RuntimeError, 'unexpected_reason'):
                close.red_control(self.environment())
        for name, content in originals.items():
            self.assertEqual((root / name).read_bytes(), content)
        self.assertFalse((root / 'phase1-close-regression/RED_CONTROL.json').exists())

    @unittest.skipUnless(shutil.which('openssl'), 'OpenSSL is required by the CI packaging contract')
    def test_ciphertext_round_trip_is_recipient_bound_and_authenticates_payload(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            private, public = root / 'fixture.key', root / 'fixture.pem'
            subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:2048', '-nodes',
                            '-keyout', str(private), '-out', str(public), '-days', '1',
                            '-subj', '/CN=Ephemeral packaging test'], check=True, capture_output=True)
            apk, encrypted = root / 'fixture.apk', root / 'fixture.cms'
            payload = b'PK\x03\x04bounded test payload\x00\xff'
            apk.write_bytes(payload)
            info = close.encrypt(apk, encrypted, public)
            self.assertNotEqual(encrypted.read_bytes(), payload)
            self.assertEqual(info['sha256'], close.sha256(encrypted))
            plain = subprocess.run(['openssl', 'cms', '-decrypt', '-binary', '-inform', 'DER',
                                    '-inkey', str(private), '-in', str(encrypted)], check=True, capture_output=True).stdout
            self.assertEqual(plain, payload)
            altered = bytearray(encrypted.read_bytes()); altered[-1] ^= 1
            encrypted.write_bytes(altered)
            failed = subprocess.run(['openssl', 'cms', '-decrypt', '-binary', '-inform', 'DER',
                                     '-inkey', str(private), '-in', str(encrypted)], capture_output=True)
            self.assertNotEqual(failed.returncode, 0)


if __name__ == '__main__':
    unittest.main()
