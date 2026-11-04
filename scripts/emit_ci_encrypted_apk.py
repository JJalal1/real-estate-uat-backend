#!/usr/bin/env python3
"""Publish only recipient-encrypted chunks of an already native-verified UAT APK."""
import argparse
import base64
import hashlib
import json
import math
import os
from pathlib import Path
import subprocess


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--log-fallback', action='store_true')
    parser.add_argument('--upgrade-predecessor', action='store_true')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    policy = json.loads((root / 'docs/PUBLIC_UAT_DELIVERY.json').read_text())
    event = json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text())
    assert event['repository']['private'] is False
    assert policy['repository'] == os.environ['GITHUB_REPOSITORY'] == event['repository']['full_name']
    assert policy['apk_delivery'] == 'recipient-encrypted-cms-only' and policy['plaintext_public_artifacts'] is False
    recipient = root / policy['recipient_certificate']
    assert hashlib.sha256(recipient.read_bytes()).hexdigest() == policy['recipient_sha256']
    proof = json.loads((root / ('dist/UPGRADE_PREDECESSOR_VERIFICATION.json' if args.upgrade_predecessor else 'dist/APK_VERIFICATION.json')).read_text())
    assert proof['source_commit'] == os.environ['GITHUB_SHA'] == os.environ['SOURCE_COMMIT']
    assert proof['version_code'] == 1000 + int(os.environ['GITHUB_RUN_NUMBER']) - int(args.upgrade_predecessor)
    assert proof['zip_crc'] == proof['apksigner'] == 'passed' and proof['fonts_match'] == 5
    payload_path = 'dist/uat-upgrade-predecessor.apk' if args.upgrade_predecessor else f"dist/real-estate-broker-uat-{os.environ['GITHUB_RUN_NUMBER']}.apk"
    payload = (root / payload_path).read_bytes()
    assert len(payload) == proof['bytes'] and hashlib.sha256(payload).hexdigest() == proof['sha256']
    native = {'source_commit': proof['source_commit'], 'sha256': proof['sha256'], 'bytes': proof['bytes'],
              'chunks': math.ceil(len(payload) / 6144), 'parts': 32}
    output = root / 'encrypted-dist'
    if args.upgrade_predecessor:
        output = output / 'upgrade-predecessor'
    output.mkdir(exist_ok=True)
    (output / 'APK_VERIFICATION.json').write_text(json.dumps(proof, indent=2) + '\n')
    for part in range(32):
        first, end = native['chunks'] * part // 32, native['chunks'] * (part + 1) // 32
        block = payload[first * 6144:end * 6144]
        encrypted = subprocess.run(['openssl', 'cms', '-encrypt', '-binary', '-aes-256-gcm', '-outform', 'DER',
            '-recip', str(recipient), '-keyopt', 'rsa_padding_mode:oaep', '-keyopt', 'rsa_oaep_md:sha256'],
            input=block, capture_output=True, check=True, timeout=60).stdout
        assert encrypted[:1] == b'\x30' and not encrypted.startswith(b'PK')
        blocks = [encrypted[i:i+12000] for i in range(0, len(encrypted), 12000)]
        meta = {'native_meta': native, 'proof': proof, 'delivery_part': part, 'delivery_parts': 32,
            'first': first, 'end': end, 'recipient_sha256': policy['recipient_sha256'],
            'cipher': 'CMS-AES256GCM-RSAOAEP-SHA256', 'cipher_bytes': len(encrypted),
            'cipher_sha256': hashlib.sha256(encrypted).hexdigest(), 'cipher_chunks': len(blocks),
            'payload_bytes': len(block), 'payload_sha256': hashlib.sha256(block).hexdigest()}
        (output / f'part-{part:02}.cms').write_bytes(encrypted)
        (output / f'part-{part:02}.json').write_text(json.dumps(meta) + '\n')
        if args.log_fallback:
            print('CODEX_CMS_BEGIN ' + json.dumps(meta, sort_keys=True), flush=True)
            for index, chunk in enumerate(blocks):
                print('CODEX_CMS_DATA ' + str(index) + ' ' + base64.b64encode(chunk).decode())
            print('CODEX_CMS_END ' + str(part), flush=True)
    if not args.log_fallback:
        print(json.dumps({'encrypted_parts': 32, 'source_commit': proof['source_commit'],
                          'plaintext_publication': False, 'recipient_sha256': policy['recipient_sha256']}))


if __name__ == '__main__':
    main()
