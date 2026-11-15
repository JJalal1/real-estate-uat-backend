import base64
import contextlib
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).parents[1]))
from phase23_firebase import disabled_receipt, validate_receipt, verify_compiled_configuration
from phase23_preflight import GateError
from prepare_uat_firebase import PROJECT, SENDER, PACKAGE, write_properties
import import_ci_uat_firebase as importer


def configuration():
    return {'projectId': PROJECT, 'senderId': SENDER,
            'appId': '1:' + SENDER + ':android:' + '1234abcd' * 4,
            'apiKey': 'synthetic-client-key-never-exported'}


def google_configuration():
    config = configuration()
    return {'project_info': {'project_id': PROJECT, 'project_number': SENDER},
            'client': [{'client_info': {'mobilesdk_app_id': config['appId'],
                                       'android_client_info': {'package_name': PACKAGE}},
                        'api_key': [{'current_key': config['apiKey']}]}]}


def apk(parts=None):
    stream = io.BytesIO()
    with zipfile.ZipFile(stream, 'w') as archive:
        for name, data in (parts or {'classes.dex': b'ordinary synthetic dex'}).items():
            archive.writestr(name, data)
    stream.seek(0)
    return zipfile.ZipFile(stream)


class FirebaseEvidenceTest(unittest.TestCase):
    def test_absent_or_explicitly_disabled_configuration_stays_off(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'firebase-uat.properties'
            with apk() as archive:
                self.assertEqual(verify_compiled_configuration(archive, path), disabled_receipt())
                write_properties(configuration(), path, False)
                receipt = verify_compiled_configuration(archive, path)
            self.assertTrue(receipt['configuration_present'])
            for field in ['client_configured', 'client_push_enabled',
                          'compiled_configuration_verified', 'real_fcm_delivery_tested']:
                self.assertFalse(receipt[field])
            self.assertRegex(receipt['config_fingerprint'], r'^[a-f0-9]{64}$')
            validate_receipt(receipt)

    def test_requested_client_must_match_actual_multidex_values_and_only_safe_evidence_leaves(self):
        config = configuration()
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'firebase-uat.properties'
            write_properties(config, path, True)
            with apk({'classes.dex': (config['projectId'] + '\0' + config['senderId']).encode(),
                      'classes2.dex': (config['apiKey'] + '\0' + config['appId']).encode()}) as archive:
                receipt = verify_compiled_configuration(archive, path)
            self.assertTrue(receipt['client_configured'])
            self.assertTrue(receipt['client_push_enabled'])
            self.assertTrue(receipt['compiled_configuration_verified'])
            self.assertFalse(receipt['real_fcm_delivery_tested'])
            for value in config.values():
                self.assertNotIn(value, json.dumps(receipt))
            for field in config:
                # Sender ID is also part of the valid app ID. Remove both in
                # that case so this exercises actual missing compiled bytes.
                excluded = {field, 'appId'} if field == 'senderId' else {field}
                with self.subTest(missing=field), apk({'classes.dex': '\0'.join(
                        value for key, value in config.items() if key not in excluded).encode()}) as archive:
                    with self.assertRaisesRegex(GateError, '^compiled_uat_firebase_configuration_mismatch$'):
                        verify_compiled_configuration(archive, path)

    def test_properties_cannot_forge_identity_fingerprint_or_include_extra_fields(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / 'firebase-uat.properties'
            write_properties(configuration(), path, True)
            original = path.read_text()
            mutations = [
                original.replace('aqer-yemen', 'other-project'),
                original.replace(SENDER, '000000000000'),
                original.replace('enabled=true', 'enabled=TRUE'),
                original.replace('fingerprint=', 'unknown='),
                original + 'aqer.uat.firebase.apiKey=SENSITIVE_SENTINEL\n',
                original + 'private_key=SENSITIVE_SENTINEL\n',
                original.replace('synthetic-client-key-never-exported', 'different-client-key-no-matching-fingerprint'),
                'SENSITIVE_SENTINEL',
                'x' * 65537,
            ]
            for changed in mutations:
                path.write_text(changed)
                with self.subTest(size=len(changed)), apk() as archive:
                    with self.assertRaisesRegex(GateError, '^uat_firebase_properties_invalid$') as caught:
                        verify_compiled_configuration(archive, path)
                    self.assertNotIn('SENSITIVE_SENTINEL', str(caught.exception))

    def test_server_private_key_is_rejected_even_when_client_configuration_is_absent(self):
        with tempfile.TemporaryDirectory() as folder:
            for kind in ['', 'RSA ', 'EC ']:
                with self.subTest(kind=kind), apk({'classes2.dex':
                        ('prefix-----BEGIN ' + kind + 'PRIVATE KEY-----SENSITIVE_SENTINEL').encode()}) as archive:
                    with self.assertRaisesRegex(GateError, '^server_private_key_forbidden_in_android$'):
                        verify_compiled_configuration(archive, Path(folder) / 'missing')

    def test_receipts_reject_unverified_claims_and_secret_fields(self):
        good = disabled_receipt()
        for bad in [dict(good, client_configured=1), dict(good, real_fcm_delivery_tested=True),
                    dict(good, client_push_enabled=True), dict(good, config_fingerprint='a' * 64),
                    dict(good, api_key='SENSITIVE_SENTINEL')]:
            with self.subTest(fields=list(bad)), self.assertRaises(GateError):
                validate_receipt(bad)

    def test_existing_importer_missing_clears_stale_configuration_and_configured_import_is_verified(self):
        with tempfile.TemporaryDirectory() as folder:
            script = Path(folder) / 'scripts/import_ci_uat_firebase.py'
            output = Path(folder) / 'mobile_app/android/firebase-uat.properties'
            output.parent.mkdir(parents=True)
            output.write_text('stale configuration')
            log = io.StringIO()
            with patch.object(importer, '__file__', str(script)), patch.dict(os.environ, {}, clear=True), contextlib.redirect_stdout(log):
                self.assertEqual(importer.main(), 0)
            self.assertFalse(output.exists())
            self.assertFalse(json.loads(log.getvalue())['client_push_enabled'])
            encoded = base64.b64encode(json.dumps(google_configuration()).encode()).decode()
            log = io.StringIO()
            with patch.object(importer, '__file__', str(script)), patch.dict(os.environ,
                    {'AQER_UAT_GOOGLE_SERVICES_JSON_BASE64': encoded}, clear=True), contextlib.redirect_stdout(log):
                self.assertEqual(importer.main(), 0)
            config = configuration()
            with apk({'classes.dex': '\0'.join(config.values()).encode()}) as archive:
                self.assertTrue(verify_compiled_configuration(archive, output)['client_configured'])
            self.assertNotIn(config['apiKey'], log.getvalue())
            self.assertNotIn(config['appId'], log.getvalue())
            self.assertEqual(output.stat().st_mode & 0o777, 0o600)

    def test_existing_importer_rejects_bad_or_server_configuration_without_echoing_it(self):
        for raw in ['SENSITIVE_SENTINEL', base64.b64encode(b'{"private_key":"SENSITIVE_SENTINEL"}').decode()]:
            with tempfile.TemporaryDirectory() as folder:
                script = Path(folder) / 'scripts/import_ci_uat_firebase.py'
                log = io.StringIO()
                with patch.object(importer, '__file__', str(script)), patch.dict(os.environ,
                        {'AQER_UAT_GOOGLE_SERVICES_JSON_BASE64': raw}, clear=True), contextlib.redirect_stdout(log):
                    self.assertEqual(importer.main(), 1)
                self.assertNotIn('SENSITIVE_SENTINEL', log.getvalue())
                self.assertFalse((Path(folder) / 'mobile_app/android/firebase-uat.properties').exists())


if __name__ == '__main__':
    unittest.main()
