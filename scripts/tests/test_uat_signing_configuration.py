"""Pure guards plus synthetic local keytool tests; no real credentials or keys."""
import base64
import contextlib
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import stat
import subprocess
import tempfile
import unittest
from unittest import mock


SCRIPT = Path(__file__).resolve().parents[1] / 'import_ci_uat_signing.py'
SPEC = importlib.util.spec_from_file_location('uat_signing', SCRIPT)
signing = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(signing)


def ci_environment(root, raw=b'synthetic invalid keystore', fingerprint='a' * 64):
    return {
        'GITHUB_ACTIONS': 'true', 'GITHUB_REPOSITORY': signing.REPOSITORY,
        'GITHUB_REF': signing.BRANCH, 'GITHUB_EVENT_NAME': 'push',
        'AQER_SIGNING_ENVIRONMENT': 'uat', 'RUNNER_TEMP': str(root),
        'GITHUB_ENV': str(root / 'github-env'),
        'AQER_UAT_KEYSTORE_BASE64': base64.b64encode(raw).decode(),
        'AQER_RELEASE_STORE_PASSWORD': 'synthetic-store-password',
        'AQER_RELEASE_KEY_ALIAS': 'fixture-signing',
        'AQER_RELEASE_KEY_PASSWORD': 'synthetic-key-password',
        'AQER_UAT_SIGNING_CERT_SHA256': fingerprint,
    }


class SigningConfigurationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.envfile = self.root / 'github-env'
        self.envfile.write_text('EXISTING=unchanged\n')
        self.env = ci_environment(self.root)

    def assert_unchanged(self):
        self.assertEqual(self.envfile.read_text(), 'EXISTING=unchanged\n')
        self.assertFalse((self.root / signing.STAGING_DIRECTORY).exists())

    def test_optional_absence_does_not_open_paths_or_change_files(self):
        absent = {key: value for key, value in self.env.items() if key not in signing.INPUTS}
        with mock.patch.object(signing, 'open_runner_paths', side_effect=AssertionError):
            self.assertEqual(signing.import_signing(absent), {'uat_signing_configured': False})
        self.assert_unchanged()

    def test_required_absence_and_each_missing_input_fail_closed(self):
        with self.assertRaises(signing.SigningError):
            signing.import_signing({}, required=True)
        for name in signing.INPUTS:
            with self.subTest(name=name):
                env = dict(self.env)
                del env[name]
                with self.assertRaises(signing.SigningError):
                    signing.import_signing(env)
                self.assert_unchanged()

    def test_stale_store_path_rejected_even_with_all_inputs_absent(self):
        with self.assertRaises(signing.SigningError):
            signing.import_signing({'AQER_RELEASE_STORE_FILE': '/old/key.jks'})

    def test_malformed_encoding_bounds_pins_and_multiline_credentials(self):
        cases = [
            ('AQER_UAT_KEYSTORE_BASE64', 'not base64!'),
            ('AQER_UAT_KEYSTORE_BASE64', 'YQ==\n'),
            ('AQER_UAT_KEYSTORE_BASE64', base64.b64encode(b'a' * (signing.MAX_KEYSTORE_BYTES + 1)).decode()),
            ('AQER_UAT_SIGNING_CERT_SHA256', 'not-a-pin'),
            ('AQER_UAT_SIGNING_CERT_SHA256', 'aa:' * 32),
            ('AQER_RELEASE_KEY_ALIAS', '-unsafe'),
            ('AQER_RELEASE_KEY_ALIAS', 'alias\nINJECTED=true'),
            ('AQER_RELEASE_STORE_PASSWORD', 'password\nINJECTED=true'),
            ('AQER_RELEASE_KEY_PASSWORD', 'password\x00'),
            ('AQER_RELEASE_KEY_PASSWORD', '   '),
        ]
        for name, value in cases:
            with self.subTest(name=name, length=len(value)):
                with self.assertRaises(signing.SigningError):
                    signing.import_signing({**self.env, name: value})
                self.assert_unchanged()

    def test_repository_branch_event_and_environment_guards(self):
        cases = [('GITHUB_ACTIONS', 'false'), ('GITHUB_REPOSITORY', 'other/repo'),
                 ('GITHUB_REF', 'refs/heads/main'), ('GITHUB_EVENT_NAME', 'pull_request'),
                 ('AQER_SIGNING_ENVIRONMENT', 'production')]
        for name, value in cases:
            with self.subTest(name=name):
                with self.assertRaises(signing.SigningError):
                    signing.import_signing({**self.env, name: value})
                self.assert_unchanged()

    def test_newlines_relative_paths_and_external_environment_file_rejected(self):
        for name, value in [('RUNNER_TEMP', str(self.root) + '\nINJECTED=true'),
                            ('RUNNER_TEMP', 'relative'),
                            ('GITHUB_ENV', str(self.root) + '\nINJECTED=true'),
                            ('GITHUB_ENV', '/tmp/outside-github-env')]:
            with self.subTest(name=name, value=value):
                with self.assertRaises((signing.SigningError, OSError)):
                    signing.import_signing({**self.env, name: value})
                self.assert_unchanged()

    def test_symlink_temp_root_rejected(self):
        linked = self.root / 'linked'
        linked.symlink_to(self.root, target_is_directory=True)
        with self.assertRaises(signing.SigningError):
            signing.import_signing({**self.env, 'RUNNER_TEMP': str(linked),
                                    'GITHUB_ENV': str(linked / 'github-env')})
        self.assert_unchanged()

    def test_symlink_environment_file_rejected_without_touching_target(self):
        linked = self.root / 'linked-env'
        linked.symlink_to(self.envfile)
        with self.assertRaises((signing.SigningError, OSError)):
            signing.import_signing({**self.env, 'GITHUB_ENV': str(linked)})
        self.assert_unchanged()

    def test_preexisting_directory_or_symlink_never_reused_or_deleted(self):
        staged = self.root / signing.STAGING_DIRECTORY
        staged.mkdir()
        marker = staged / 'belongs-to-previous-job'
        marker.write_text('preserve')
        with self.assertRaises(OSError):
            signing.import_signing(self.env)
        self.assertEqual(marker.read_text(), 'preserve')
        marker.unlink()
        staged.rmdir()
        staged.symlink_to(self.root, target_is_directory=True)
        with self.assertRaises(OSError):
            signing.import_signing(self.env)
        self.assertTrue(staged.is_symlink())
        self.assertEqual(self.envfile.read_text(), 'EXISTING=unchanged\n')

    def test_fifo_environment_file_rejected_without_waiting_for_a_reader(self):
        fifo = self.root / 'environment-fifo'
        os.mkfifo(fifo)
        with self.assertRaises((signing.SigningError, OSError)):
            signing.import_signing({**self.env, 'GITHUB_ENV': str(fifo)})
        self.assert_unchanged()

    def test_world_writable_runner_or_environment_file_rejected(self):
        for path in (self.root, self.envfile):
            with self.subTest(path=path.name):
                original = stat.S_IMODE(path.stat().st_mode)
                path.chmod(original | 0o002)
                try:
                    with self.assertRaises(signing.SigningError):
                        signing.import_signing(self.env)
                finally:
                    path.chmod(original)
                self.assert_unchanged()

    def test_keytool_exception_output_and_input_values_never_logged(self):
        sensitive = 'private-diagnostic-marker'
        with mock.patch.dict(os.environ, self.env, clear=True), \
                mock.patch.object(signing.shutil, 'which', return_value='/usr/bin/keytool'), \
                mock.patch.object(signing.subprocess, 'run', side_effect=subprocess.TimeoutExpired(
                    sensitive, 30, output=sensitive.encode(), stderr=sensitive.encode())):
            stdout, stderr = io.StringIO(), io.StringIO()
            with contextlib.redirect_stdout(stdout), contextlib.redirect_stderr(stderr):
                self.assertEqual(signing.main([]), 1)
        output = stdout.getvalue() + stderr.getvalue()
        for value in [sensitive, *[self.env[name] for name in signing.INPUTS]]:
            self.assertNotIn(value, output)
        self.assert_unchanged()

    def test_subprocess_receives_password_env_references_and_no_unrelated_secret(self):
        config = signing.read_configuration(self.env)
        config['fingerprint'] = hashlib.sha256(b'fake-der-certificate').hexdigest()
        success = subprocess.CompletedProcess([], 0, b'fake-der-certificate', b'')
        listing = subprocess.CompletedProcess([], 0, b'Keystore type: JKS\n', b'')
        with mock.patch.object(signing.shutil, 'which', return_value='/usr/bin/keytool'), \
                mock.patch.object(signing.subprocess, 'run', side_effect=[listing, success, success]) as run:
            signing.validate_keystore(self.root / 'key.jks', config)
        self.assertEqual(run.call_count, 3)
        for call in run.call_args_list:
            args = call.args[0]
            self.assertNotIn(config['store_password'], args)
            self.assertNotIn(config['key_password'], args)
            self.assertIn('-storepass:env', args)
            self.assertEqual(call.kwargs['stdin'], subprocess.DEVNULL)
            self.assertEqual(call.kwargs['timeout'], 30)
            self.assertNotIn('AQER_UAT_KEYSTORE_BASE64', call.kwargs['env'])
            self.assertNotIn('JAVA_TOOL_OPTIONS', call.kwargs['env'])
        self.assertIn('-keypass:env', run.call_args_list[2].args[0])

    def test_export_failure_cleans_only_created_key(self):
        with mock.patch.object(signing, 'validate_keystore'), \
                mock.patch.object(signing.os, 'write', side_effect=OSError('synthetic failure')):
            with self.assertRaises(OSError):
                signing.import_signing(self.env)
        self.assert_unchanged()


@unittest.skipUnless(shutil.which('keytool') or os.environ.get('AQER_TEST_RUNNER_SIGNING') == 'true',
                     'Java keytool is required for synthetic integration tests')
class RealKeytoolSigningTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture_dir = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.fixture_dir.cleanup)
        cls.fixture = Path(cls.fixture_dir.name)
        cls.keytool = shutil.which('keytool')
        if not cls.keytool:
            raise AssertionError('The opted-in runner signing test requires Java keytool.')
        cls.password_env = {**os.environ,
                            'TEST_UAT_STORE_PASSWORD': 'synthetic-store-password',
                            'TEST_UAT_KEY_PASSWORD': 'synthetic-key-password'}
        cls.keystore = cls.fixture / 'synthetic.jks'
        cls.invoke('-genkeypair', '-keystore', str(cls.keystore), '-storetype', 'JKS',
                   '-alias', 'fixture-signing', '-keyalg', 'RSA', '-keysize', '2048',
                   '-validity', '1', '-dname', 'CN=Synthetic UAT Test Only',
                   '-storepass:env', 'TEST_UAT_STORE_PASSWORD',
                   '-keypass:env', 'TEST_UAT_KEY_PASSWORD', '-noprompt')
        cls.certificate = cls.invoke('-exportcert', '-keystore', str(cls.keystore),
                                     '-alias', 'fixture-signing',
                                     '-storepass:env', 'TEST_UAT_STORE_PASSWORD')
        cls.fingerprint = hashlib.sha256(cls.certificate).hexdigest()
        certfile = cls.fixture / 'synthetic.der'
        certfile.write_bytes(cls.certificate)
        cls.trusted_store = cls.fixture / 'certificate-only.jks'
        cls.invoke('-importcert', '-keystore', str(cls.trusted_store), '-storetype', 'JKS',
                   '-alias', 'fixture-signing', '-file', str(certfile),
                   '-storepass:env', 'TEST_UAT_STORE_PASSWORD', '-noprompt')
        cls.pkcs12 = cls.fixture / 'synthetic.p12'
        cls.invoke('-importkeystore', '-srckeystore', str(cls.keystore),
                   '-srcalias', 'fixture-signing', '-srcstorepass:env', 'TEST_UAT_STORE_PASSWORD',
                   '-srckeypass:env', 'TEST_UAT_KEY_PASSWORD', '-destkeystore', str(cls.pkcs12),
                   '-deststoretype', 'PKCS12', '-deststorepass:env', 'TEST_UAT_STORE_PASSWORD',
                   '-destkeypass:env', 'TEST_UAT_STORE_PASSWORD', '-noprompt')

    @classmethod
    def invoke(cls, *args):
        result = subprocess.run([cls.keytool, *args], env=cls.password_env,
                                stdin=subprocess.DEVNULL, capture_output=True, timeout=30)
        if result.returncode:
            raise AssertionError('Synthetic keytool fixture setup failed; diagnostics suppressed.')
        return result.stdout

    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.envfile = self.root / 'github-env'
        self.envfile.write_text('EXISTING=unchanged\n')
        self.env = ci_environment(self.root, self.keystore.read_bytes(), self.fingerprint)

    def assert_rejected_and_clean(self, overrides):
        with self.assertRaises(signing.SigningError):
            signing.import_signing({**self.env, **overrides}, required=True)
        self.assertFalse((self.root / signing.STAGING_DIRECTORY).exists())
        self.assertEqual(self.envfile.read_text(), 'EXISTING=unchanged\n')

    def test_valid_private_key_exports_only_public_fields_with_restrictive_permissions(self):
        colon_pin = ':'.join(self.fingerprint[i:i + 2] for i in range(0, 64, 2)).upper()
        receipt = signing.import_signing({**self.env, 'AQER_UAT_SIGNING_CERT_SHA256': colon_pin}, required=True)
        staged_dir = self.root / signing.STAGING_DIRECTORY
        staged = staged_dir / signing.KEYSTORE_FILENAME
        self.assertEqual(stat.S_IMODE(staged_dir.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE(staged.stat().st_mode), 0o600)
        self.assertEqual(staged.read_bytes(), self.keystore.read_bytes())
        self.assertEqual(receipt, {'uat_signing_configured': True,
                                  'certificate_sha256': self.fingerprint, 'scope': 'uat'})
        exported = self.envfile.read_text()
        self.assertIn(f'AQER_RELEASE_STORE_FILE={staged}\n', exported)
        self.assertIn('AQER_ALLOW_DEBUG_RELEASE_SIGNING=false\n', exported)
        self.assertIn('AQER_UAT_SIGNING_CONFIGURED=true\n', exported)
        for name in signing.INPUTS[:4]:
            self.assertNotIn(self.env[name], exported + json.dumps(receipt))
            self.assertNotIn(name + '=', exported)
        self.assertEqual(self.env['AQER_RELEASE_KEY_PASSWORD'], 'synthetic-key-password')

    def test_wrong_store_and_private_key_passwords_fail_closed(self):
        for name in ('AQER_RELEASE_STORE_PASSWORD', 'AQER_RELEASE_KEY_PASSWORD'):
            with self.subTest(name=name):
                self.assert_rejected_and_clean({name: 'incorrect-synthetic-password'})

    def test_wrong_approved_certificate_fails_closed(self):
        self.assert_rejected_and_clean({'AQER_UAT_SIGNING_CERT_SHA256': '0' * 64})

    def test_pkcs12_wrong_private_key_password_fails_closed(self):
        self.assert_rejected_and_clean({
            'AQER_UAT_KEYSTORE_BASE64': base64.b64encode(self.pkcs12.read_bytes()).decode(),
            'AQER_RELEASE_KEY_PASSWORD': 'incorrect-synthetic-password'})

    def test_pkcs12_matching_passwords_are_accepted(self):
        receipt = signing.import_signing({
            **self.env, 'AQER_UAT_KEYSTORE_BASE64': base64.b64encode(self.pkcs12.read_bytes()).decode(),
            'AQER_RELEASE_KEY_PASSWORD': self.env['AQER_RELEASE_STORE_PASSWORD']}, required=True)
        self.assertTrue(receipt['uat_signing_configured'])

    def test_certificate_only_alias_cannot_pass_private_key_validation(self):
        self.assert_rejected_and_clean({
            'AQER_UAT_KEYSTORE_BASE64': base64.b64encode(self.trusted_store.read_bytes()).decode()})

    def test_invalid_keystore_and_unknown_alias_fail_closed(self):
        self.assert_rejected_and_clean({'AQER_UAT_KEYSTORE_BASE64': base64.b64encode(b'not a key').decode()})
        self.assert_rejected_and_clean({'AQER_RELEASE_KEY_ALIAS': 'missing-alias'})

    @unittest.skipUnless(os.environ.get('AQER_TEST_RUNNER_SIGNING') == 'true',
                         'Opt in only in the phase23 CI contract job')
    def test_actual_runner_paths_with_synthetic_key_and_isolated_environment_file(self):
        # Check the real GitHub paths/permissions, but never export test signing
        # values to the real GITHUB_ENV or read/use any signing secret from CI.
        signing.guard(os.environ)
        root, root_fd, env_fd = signing.open_runner_paths(os.environ)
        os.close(env_fd)
        os.close(root_fd)
        actual_env = Path(os.environ['GITHUB_ENV'])
        before = actual_env.read_bytes()
        staged_dir = root / signing.STAGING_DIRECTORY
        staged_key = staged_dir / signing.KEYSTORE_FILENAME
        owned_staging = False
        with tempfile.NamedTemporaryFile(mode='w+', encoding='utf-8', dir=root,
                                         prefix='aqer-signing-smoke-env-') as isolated_env:
            isolated_env.write('EXISTING=unchanged\n')
            isolated_env.flush()
            env = ci_environment(root, self.keystore.read_bytes(), self.fingerprint)
            env['GITHUB_ENV'] = isolated_env.name
            try:
                receipt = signing.import_signing(env, required=True)
                owned_staging = receipt['uat_signing_configured']
                self.assertTrue(owned_staging)
                self.assertEqual(stat.S_IMODE(staged_key.stat().st_mode), 0o600)
                self.assertEqual(stat.S_IMODE(staged_dir.stat().st_mode), 0o700)
                self.assertTrue(staged_key.read_bytes() == self.keystore.read_bytes())
                isolated_env.seek(0)
                self.assertIn('AQER_ALLOW_DEBUG_RELEASE_SIGNING=false\n', isolated_env.read())
            finally:
                if owned_staging:
                    staged_key.unlink()
                    staged_dir.rmdir()
        self.assertTrue(actual_env.read_bytes() == before, 'Real GITHUB_ENV must remain unchanged')
        self.assertFalse(staged_dir.exists())


if __name__ == '__main__':
    unittest.main()
