import contextlib
import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'prepare_uat_firebase.py'
spec = importlib.util.spec_from_file_location('uat_firebase', SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def fixture():
    return {'project_info': {'project_id': 'aqer-yemen', 'project_number': '982331876719'},
            'client': [{'client_info': {'mobilesdk_app_id': '1:982331876719:android:' + '1234abcd' * 4,
                       'android_client_info': {'package_name': 'com.aqer.yemen.uat'}},
                        'api_key': [{'current_key': 'synthetic-client-key-not-a-real-secret'}]}]}


class UatFirebaseConfigurationTest(unittest.TestCase):
    def test_selects_the_exact_uat_client_from_a_multiclient_export(self):
        data = fixture()
        other = copy.deepcopy(data['client'][0]); other['client_info']['android_client_info']['package_name'] = 'com.example.other'
        data['client'].insert(0, other)
        actual = module.validate(json.dumps(data).encode())
        self.assertEqual('aqer-yemen', actual['projectId'])
        self.assertEqual('synthetic-client-key-not-a-real-secret', actual['apiKey'])

    def test_rejects_wrong_identity_missing_and_duplicate_clients(self):
        variants = []
        for key in ['project_id', 'project_number']:
            data = fixture(); data['project_info'][key] = 'wrong'; variants.append(data)
        data = fixture(); data['client'][0]['client_info']['android_client_info']['package_name'] = 'com.example.real_estate_mobile'; variants.append(data)
        data = fixture(); data['client'].append(copy.deepcopy(data['client'][0])); variants.append(data)
        data = fixture(); data['client'][0]['client_info']['mobilesdk_app_id'] = '1:000:android:12345678'; variants.append(data)
        for data in variants:
            with self.subTest(data=data), self.assertRaises(ValueError):
                module.validate(json.dumps(data).encode())

    def test_rejects_server_credentials_at_any_depth_and_duplicate_json_keys(self):
        for key in ['private_key', 'private_key_id', 'client_secret', 'refresh_token']:
            data = fixture(); data['client'][0]['nested'] = {key: 'SENSITIVE_SENTINEL'}
            with self.subTest(key=key), self.assertRaisesRegex(ValueError, 'Server credentials'):
                module.validate(json.dumps(data).encode())
        with self.assertRaisesRegex(ValueError, 'Duplicate'):
            module.validate(b'{"project_info":{},"project_info":{}}')

    def test_rejects_oversize_malformed_nonobject_and_control_characters(self):
        values = [b'x' * 65537, b'', b'[]', b'null', b'\xff', b'{']
        data = fixture(); data['client'][0]['api_key'][0]['current_key'] = 'public-key\nAQER_PUSH_ENABLED=true'; values.append(json.dumps(data).encode())
        for raw in values:
            with self.subTest(size=len(raw)), self.assertRaises(ValueError):
                module.validate(raw)

    def test_cli_keeps_client_key_out_of_logs_and_writes_private_atomic_properties(self):
        with tempfile.TemporaryDirectory() as td:
            source = Path(td) / 'google-services.json'; target = Path(td) / 'generated.properties'
            source.write_text(json.dumps(fixture()))
            result = subprocess.run([sys.executable, str(SCRIPT), '--config', str(source), '--out', str(target), '--enable-client'], capture_output=True, text=True)
            self.assertEqual(0, result.returncode, result.stdout)
            self.assertNotIn('synthetic-client-key', result.stdout + result.stderr)
            self.assertEqual(0o600, stat.S_IMODE(target.stat().st_mode))
            self.assertIn('aqer.uat.firebase.enabled=true', target.read_text())
            self.assertIn('aqer.uat.firebase.projectId=aqer-yemen', target.read_text())
            self.assertEqual([], list(Path(td).glob('.firebase-uat-*')))
            original = target.read_bytes(); source.write_text('{"private_key":"SENSITIVE_SENTINEL"}')
            result = subprocess.run([sys.executable, str(SCRIPT), '--config', str(source), '--out', str(target)], capture_output=True, text=True)
            self.assertNotEqual(0, result.returncode)
            self.assertNotIn('SENSITIVE_SENTINEL', result.stdout + result.stderr)
            self.assertEqual(original, target.read_bytes())


if __name__ == '__main__':
    unittest.main()
