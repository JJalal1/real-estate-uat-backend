#!/usr/bin/env python3
"""Locally decrypt the owner's CMS UAT package. Never upload or print a private key.

Requires Python 3 and OpenSSL. The expected source must come from the owner report.
"""
import argparse
import getpass
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import zipfile

RECIPIENT = '0705dcb18aa84e9ca35d0f3985c8e1999739a25a9dbedd5cff5d07161f4b6ced'
PACKAGE = 'com.aqer.yemen.uat'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--artifact', required=True, type=Path)
    parser.add_argument('--key', required=True, type=Path)
    parser.add_argument('--out', required=True, type=Path)
    parser.add_argument('--expected-source', required=True)
    parser.add_argument('--ask-passphrase', action='store_true')
    parser.add_argument('--expected-artifact-sha256', required=True)
    args = parser.parse_args()
    if len(args.expected_source) != 40 or any(c not in '0123456789abcdef' for c in args.expected_source):
        raise ValueError('Expected the complete source SHA from the owner report')
    if len(args.expected_artifact_sha256) != 64 or any(c not in '0123456789abcdef' for c in args.expected_artifact_sha256):
        raise ValueError('Expected the complete package SHA256 from the owner report')
    with args.artifact.open('rb') as source_file:
        file_hash = hashlib.sha256()
        for block in iter(lambda: source_file.read(1024 * 1024), b''):
            file_hash.update(block)
        digest = file_hash.hexdigest()
    if digest != args.expected_artifact_sha256:
        raise ValueError('The downloaded owner package does not match the report; nothing was decrypted')
    if not args.key.is_file():
        raise ValueError('Use the existing approved private key on your own computer')
    environment = dict(os.environ)
    extra = []
    if args.ask_passphrase:
        environment['AQER_LOCAL_KEY_PASSPHRASE'] = getpass.getpass('Local private-key passphrase: ')
        extra = ['-passin', 'env:AQER_LOCAL_KEY_PASSPHRASE']

    def decrypt(cipher):
        result = subprocess.run(['openssl', 'cms', '-decrypt', '-binary', '-inform', 'DER',
                                 '-inkey', str(args.key), *extra], input=cipher,
                                capture_output=True, env=environment, timeout=90)
        if result.returncode:
            raise ValueError('CMS decryption failed; check the local key/passphrase. No APK was accepted.')
        return result.stdout

    args.out.mkdir(parents=True, exist_ok=True, mode=0o700)
    prepared = []
    with tempfile.TemporaryDirectory(prefix='aqer-owner-', dir=args.out) as temporary:
        with zipfile.ZipFile(args.artifact) as archive:
            if len(set(archive.namelist())) != len(archive.namelist()):
                raise ValueError('Duplicate archive members')
            if sum(i.file_size for i in archive.infolist()) > 512 * 1024 * 1024:
                raise ValueError('Archive exceeds the bounded owner package budget')

            def read(name, limit):
                if archive.getinfo(name).file_size > limit:
                    raise ValueError('Invalid bounded member ' + name)
                return archive.read(name)

            proofs = []
            for prefix in ['upgrade-predecessor/', '']:
                proof = json.loads(read(prefix + 'APK_VERIFICATION.json', 1024 * 1024))
                if proof['source_commit'] != args.expected_source or proof['package'] != PACKAGE:
                    raise ValueError('Wrong source/package; do not install it')
                if proof['apksigner'] != 'passed' or proof['zip_crc'] != 'passed':
                    raise ValueError('Missing CI native verification')
                total = 0
                digest = hashlib.sha256()
                part_end = 0
                target = Path(temporary) / ('A.apk' if prefix else 'B.apk')
                with target.open('xb') as output:
                    os.chmod(target, 0o600)
                    for part in range(32):
                        meta = json.loads(read(prefix + f'part-{part:02}.json', 1024 * 1024))
                        cipher = read(prefix + f'part-{part:02}.cms', 8 * 1024 * 1024)
                        if (meta['recipient_sha256'] != RECIPIENT or meta['delivery_part'] != part
                                or meta['delivery_parts'] != 32 or meta['proof'] != proof
                                or meta['cipher'] != 'CMS-AES256GCM-RSAOAEP-SHA256'
                                or meta['native_meta']['source_commit'] != args.expected_source
                                or meta['native_meta']['sha256'] != proof['sha256']
                                or meta['first'] != part_end):
                            raise ValueError('Part identity/order mismatch')
                        if len(cipher) != meta['cipher_bytes'] or hashlib.sha256(cipher).hexdigest() != meta['cipher_sha256']:
                            raise ValueError('Ciphertext integrity mismatch')
                        block = decrypt(cipher)
                        if len(block) != meta['payload_bytes'] or hashlib.sha256(block).hexdigest() != meta['payload_sha256']:
                            raise ValueError('Decrypted part integrity mismatch')
                        part_end = meta['end']
                        total += len(block)
                        digest.update(block)
                        output.write(block)
                if total != proof['bytes'] or digest.hexdigest() != proof['sha256']:
                    raise ValueError('Final APK SHA256 mismatch')
                with zipfile.ZipFile(target) as apk:
                    if apk.testzip() is not None:
                        raise ValueError('Corrupted APK ZIP')
                proofs.append(proof)
                prepared.append((target, args.out / f"aqer-owner-uat-{proof['version_code']}.apk"))
            if proofs[0]['certificate_sha256'] != proofs[1]['certificate_sha256'] or proofs[0]['version_code'] + 1 != proofs[1]['version_code']:
                raise ValueError('The A/B pair is not compatible for package replacement')
            upgrade = json.loads(read('ANDROID_UPGRADE_VERIFICATION.json', 2 * 1024 * 1024))
            if upgrade['source_commit'] != args.expected_source or upgrade['status'] != 'passed' or not upgrade['same_certificate']:
                raise ValueError('The package has no passing Android upgrade proof')
            has_access = 'OWNER_ACCESS.cms' in archive.namelist()
            if has_access:
                access = decrypt(read('OWNER_ACCESS.cms', 65536))
                decoded = json.loads(access)
                if decoded.get('manifest', {}).get('fixture_only') is not True:
                    raise ValueError('Not a synthetic UAT access capsule')
                target = Path(temporary) / 'owner-access.json'
                target.write_bytes(access)
                os.chmod(target, 0o600)
                prepared.append((target, args.out / 'owner-access.json'))
        if any(destination.exists() for _, destination in prepared):
            raise ValueError('An output already exists; choose a new empty output directory')
        for source, destination in prepared:
            # Hard-link only complete, validated files; never overwrite an existing output.
            os.link(source, destination)
        for proof in proofs:
            print(f"UAT APK {proof['version_code']} SHA256 {proof['sha256']}")
        print('Verified source: ' + args.expected_source)
        print('Install A first, then replace it with B; retain the owner report and compare its hashes.')
        if has_access:
            print('Owner-only account details are in owner-access.json; do not publish that file.')


if __name__ == '__main__':
    main()
