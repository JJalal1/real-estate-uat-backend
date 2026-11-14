import io
import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).parents[1]))
import prepare_phase23_visual_delivery as delivery
from phase23_preflight import GateError
from phase23_firebase import disabled_receipt


def library(payload, alignment=16384):
    data = bytearray(120)
    data[:6] = b'\x7fELF\x02\x01'
    struct.pack_into('<Q', data, 32, 64)
    struct.pack_into('<HH', data, 54, 56, 1)
    struct.pack_into('<I', data, 64, 1)
    struct.pack_into('<Q', data, 112, alignment)
    return bytes(data) + payload


def apk_bytes(change=None, dex=b'fixture dex with no client configuration'):
    payload = delivery.API.encode() + b'\0' + delivery.SHARE_BASE.encode() + b'\0'
    entries = {f'lib/{abi}/libapp.so': library(payload) for abi in delivery.ABIS}
    entries['classes.dex'] = dex
    if change:
        change(entries)
    stream = io.BytesIO()
    with zipfile.ZipFile(stream, 'w') as archive:
        for name, value in entries.items():
            archive.writestr(name, value)
    return stream.getvalue()


class VisualDeliveryTest(unittest.TestCase):
    def verify(self, data, properties=None):
        with tempfile.TemporaryDirectory() as directory, zipfile.ZipFile(io.BytesIO(data)) as archive:
            return delivery.verify_archive(archive, properties or Path(directory) / 'absent.properties')

    def test_ordinary_main_contract_three_abis_16kb_and_disabled_firebase(self):
        self.assertEqual(self.verify(apk_bytes()), disabled_receipt())

    def test_every_synthetic_marker_in_any_abi_blocks_owner_delivery(self):
        for marker in delivery.FORBIDDEN_MARKERS:
            for abi in delivery.ABIS:
                name = f'lib/{abi}/libapp.so'
                with self.subTest(marker=marker, abi=abi), self.assertRaisesRegex(GateError, 'test_target_forbidden'):
                    self.verify(apk_bytes(lambda e: e.update({name: e[name] + marker})))

    def test_api_prefix_alone_does_not_claim_a_compiled_share_origin(self):
        def only_api(entries):
            for name in list(entries):
                if name.endswith('libapp.so'):
                    entries[name] = library(delivery.API.encode())
        with self.assertRaisesRegex(GateError, 'share_origin_missing'):
            self.verify(apk_bytes(only_api))
        def missing_api(entries):
            entries['lib/x86_64/libapp.so'] = library(delivery.SHARE_BASE.encode())
        with self.assertRaisesRegex(GateError, 'uat_api_missing'):
            self.verify(apk_bytes(missing_api))

    def test_missing_extra_abi_and_non_16kb_native_library_rejected(self):
        with self.assertRaisesRegex(GateError, 'three_abis'):
            self.verify(apk_bytes(lambda e: e.pop('lib/armeabi-v7a/libapp.so')))
        with self.assertRaisesRegex(GateError, 'three_abis'):
            self.verify(apk_bytes(lambda e: e.update({'lib/mips/libapp.so': b'extra'})))
        with self.assertRaisesRegex(RuntimeError, 'elf16kb_alignment_failed'):
            self.verify(apk_bytes(lambda e: e.update({'lib/x86_64/libother.so': library(b'', 4096)})))

    def test_firebase_file_or_compiled_app_id_refuses_false_off_claim(self):
        with tempfile.TemporaryDirectory() as directory:
            properties = Path(directory) / 'firebase.properties'
            properties.write_text('configuration must not be present')
            with self.assertRaisesRegex(GateError, 'firebase_configuration_forbidden'):
                self.verify(apk_bytes(), properties)
        with self.assertRaisesRegex(GateError, 'compiled_firebase_client_forbidden'):
            self.verify(apk_bytes(dex=b'1:982331876719:android:123abc'))

    def test_build_flags_are_bounded_and_ordinary(self):
        good = {'PHASE23_BUILD': '1801', 'PHASE23_PREFETCH_ON': 'true'}
        self.assertEqual(delivery.build_number(good), 1801)
        for change in [{'PHASE23_BUILD': '1610'}, {'PHASE23_BUILD': True},
                       {'PHASE23_BUILD': '2100000001'}, {'PHASE23_PREFETCH_ON': 'false'},
                       {'PHASE23_PRIVATE_PAGES': 'true'}, {'PHASE23_CALLBACK_HARNESS': 'true'}]:
            with self.subTest(change=change), self.assertRaises(GateError):
                delivery.build_number(dict(good, **change))

    def test_prepare_checks_native_tools_and_exports_ciphertext_only(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            cert = root / 'scripts/phase23_recipient.pem'
            cert.parent.mkdir()
            cert.write_text('-----BEGIN CERTIFICATE-----\nfixture\n')
            apk = root / 'mobile_app/build/app/outputs/flutter-apk/app-uat-release.apk'
            apk.parent.mkdir(parents=True)
            apk.write_bytes(apk_bytes())
            identity = {'source_commit': 'a' * 40, 'ci_run_id': '1234',
                        'product_trees': {'mobile_app': 'b' * 40, 'backend-api-runtime': 'c' * 40}}
            env = {'PHASE23_BUILD': '1801', 'PHASE23_PREFETCH_ON': 'true',
                   'PHASE23_RECIPIENT_SHA256': delivery.sha(cert), 'ANDROID_HOME': '/sdk'}
            def external(*args):
                if 'apksigner' in str(args[0]):
                    return 'Signer #1 certificate SHA-256 digest: ' + 'd' * 64
                if 'aapt' in str(args[0]):
                    return "package: name='com.aqer.yemen.uat' versionCode='1801'\nsdkVersion:'23'\ntargetSdkVersion:'36'"
                return ''
            def encrypt(source, destination, recipient):
                self.assertEqual(source.read_bytes(), apk.read_bytes())
                self.assertEqual(recipient, cert)
                destination.write_bytes(b'\x30ciphertext fixture')
                return {'file': destination.name, 'sha256': delivery.sha(destination)}
            with patch.object(delivery, 'guard', return_value=identity) as guard, \
                    patch.object(delivery, 'RECIPIENT_SHA256', delivery.sha(cert)), \
                    patch.object(delivery, 'android_tools', return_value=Path('/sdk/build-tools/36.0.0')), \
                    patch.object(delivery, 'call', side_effect=external) as call, \
                    patch.object(delivery, 'encrypt', side_effect=encrypt):
                receipt = delivery.prepare(env, root)
            guard.assert_called_once_with(env, root)
            self.assertTrue(any(c.args[1:] == ('-c', '-P', '16', '4', root / 'phase23-visual-delivery-private/target.apk') for c in call.call_args_list))
            out = root / 'phase23-visual-installer-sealed'
            self.assertEqual({p.name for p in out.iterdir()}, {'installer.cms', 'APK_VERIFICATION.json'})
            self.assertEqual(receipt['entrypoint'], 'lib/main.dart')
            self.assertFalse(receipt['owner_update_compatibility_verified'])
            self.assertFalse(receipt['native_acceptance_claimed'])
            self.assertFalse(receipt['firebase']['client_configured'])
            self.assertEqual(json.loads((out / 'APK_VERIFICATION.json').read_text()), receipt)


if __name__ == '__main__':
    unittest.main()
