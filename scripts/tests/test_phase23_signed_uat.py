import json
from pathlib import Path
import struct
import sys
import tempfile
import unittest
from unittest.mock import patch
import warnings
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import prepare_phase23_signed_uat as subject

PIN = 'a' * 64
SIGNATURE = 'Signer #1 certificate SHA-256 digest: ' + PIN + '\n'
BADGING = ("package: name='com.aqer.yemen.uat' versionCode='1612' versionName='1.0'\n"
           "sdkVersion:'23'\ntargetSdkVersion:'36'\n")


def context():
    return {'AQER_SIGNING_ENVIRONMENT': 'uat', 'AQER_UAT_SIGNING_CONFIGURED': 'true',
            'AQER_ALLOW_DEBUG_RELEASE_SIGNING': 'false', 'AQER_UAT_SIGNING_CERT_SHA256': PIN,
            'PHASE23_BUILD': '1612', 'GITHUB_RUN_ID': '123'}


def elf(alignment=16384):
    data = bytearray(120)
    data[:6] = b'\x7fELF\x02\x01'
    struct.pack_into('<Q', data, 32, 64)
    struct.pack_into('<HH', data, 54, 56, 1)
    struct.pack_into('<I', data, 64, 1)
    struct.pack_into('<Q', data, 112, alignment)
    return bytes(data) + subject.API.encode()


class SignedUatTest(unittest.TestCase):
    def test_explicit_verified_context_only(self):
        self.assertEqual(subject.signing_context(context()), (1612, PIN))
        changes = {'AQER_SIGNING_ENVIRONMENT': 'production', 'AQER_UAT_SIGNING_CONFIGURED': 'false',
                   'AQER_ALLOW_DEBUG_RELEASE_SIGNING': 'true', 'AQER_UAT_SIGNING_CERT_SHA256': PIN + '\n',
                   'PHASE23_BUILD': '1611', 'GITHUB_RUN_ID': '0'}
        for key, value in changes.items():
            with self.subTest(key=key), self.assertRaises(subject.GateError):
                subject.signing_context({**context(), key: value})
        for key in context():
            env = context()
            del env[key]
            with self.subTest(missing=key), self.assertRaises(subject.GateError):
                subject.signing_context(env)

    def test_actual_certificate_must_be_the_single_pinned_signer(self):
        subject.verify_metadata(SIGNATURE, BADGING, 1612, PIN)
        for signature in ('', SIGNATURE.replace(PIN, 'b' * 64),
                          SIGNATURE + SIGNATURE.replace('#1', '#2'),
                          SIGNATURE.replace('Signer #1', 'Source Stamp')):
            with self.subTest(signature=signature), self.assertRaises(subject.GateError):
                subject.verify_metadata(signature, BADGING, 1612, PIN)

    def test_wrong_identity_sdk_version_or_debuggable_is_rejected(self):
        for badging in (BADGING.replace('.uat', ''), BADGING.replace('1612', '1611'),
                        BADGING.replace("sdkVersion:'23'", "sdkVersion:'24'"),
                        BADGING.replace("targetSdkVersion:'36'", "targetSdkVersion:'35'"),
                        BADGING + 'application-debuggable\n', BADGING + BADGING):
            with self.subTest(badging=badging), self.assertRaises(subject.GateError):
                subject.verify_metadata(SIGNATURE, badging, 1612, PIN)

    def archive(self, folder, *, missing=None, api=True, alignment=16384, duplicate=False, private_key=False):
        apk = folder / 'fixture.apk'
        with zipfile.ZipFile(apk, 'w') as archive:
            for abi in sorted(subject.ABIS - {missing}):
                payload = elf(alignment)
                if not api:
                    payload = payload.replace(subject.API.encode(), b'https://other.invalid/api')
                archive.writestr(f'lib/{abi}/libapp.so', payload)
            archive.writestr('classes.dex', b'dex\n' + (b'-----BEGIN PRIVATE KEY-----' if private_key else b'fixture'))
            if duplicate:
                with warnings.catch_warnings():
                    warnings.simplefilter('ignore', UserWarning)
                    archive.writestr('classes.dex', b'duplicate')
        return apk

    def test_archive_proves_all_architectures_and_keeps_fcm_unclaimed(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            receipt = subject.verify_archive(self.archive(folder), folder / 'absent.properties')
        self.assertFalse(receipt['client_configured'])
        self.assertFalse(receipt['real_fcm_delivery_tested'])

    def test_incompatible_archive_never_reaches_export(self):
        for kwargs in ({'missing': 'x86_64'}, {'api': False}, {'alignment': 4096},
                       {'duplicate': True}, {'private_key': True}):
            with self.subTest(kwargs=kwargs), tempfile.TemporaryDirectory() as directory:
                folder = Path(directory)
                with self.assertRaises(RuntimeError):
                    subject.verify_archive(self.archive(folder, **kwargs), folder / 'absent.properties')

    def test_export_has_only_ciphertext_and_public_receipt(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            apk = folder / 'private.apk'
            apk.write_bytes(b'PRIVATE_APK_BYTES')
            output = folder / 'sealed'

            def encrypt(source, destination, recipient):
                self.assertEqual(source, apk)
                destination.write_bytes(b'\x30ciphertext')
                return {'file': destination.name, 'bytes': destination.stat().st_size,
                        'sha256': subject.sha256(destination), 'cipher': 'test-only'}

            with patch.object(subject.android, 'encrypt', side_effect=encrypt):
                subject.export_sealed(apk, {'certificate_sha256': PIN}, output, subject.RECIPIENT)
            self.assertEqual({path.name for path in output.iterdir()}, {'installer.cms', 'APK_VERIFICATION.json'})
            self.assertNotIn(b'PRIVATE_APK_BYTES', b''.join(path.read_bytes() for path in output.iterdir()))
            self.assertEqual(json.loads((output / 'APK_VERIFICATION.json').read_text())['certificate_sha256'], PIN)
            with patch.object(subject.android, 'encrypt') as encrypt_again, self.assertRaises(FileExistsError):
                subject.export_sealed(apk, {}, output, subject.RECIPIENT)
            encrypt_again.assert_not_called()

    def test_bad_recipient_and_partial_encryption_leave_no_upload_folder(self):
        with tempfile.TemporaryDirectory() as directory:
            folder = Path(directory)
            wrong = folder / 'wrong.pem'
            wrong.write_text('not the reviewed recipient')
            output = folder / 'sealed'
            with self.assertRaises(subject.GateError):
                subject.export_sealed(folder / 'app.apk', {}, output, wrong)
            self.assertFalse(output.exists())
            with patch.object(subject.android, 'encrypt', side_effect=RuntimeError('synthetic failure')):
                with self.assertRaises(RuntimeError):
                    subject.export_sealed(folder / 'app.apk', {}, output, subject.RECIPIENT)
            self.assertFalse(output.exists())


if __name__ == '__main__':
    unittest.main()
