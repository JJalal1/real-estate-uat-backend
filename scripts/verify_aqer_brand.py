#!/usr/bin/env python3
"""Fail closed if reviewed brand/native assets or watermark geometry drift."""
import hashlib
import json
from pathlib import Path
import struct
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def verify(root=ROOT):
    manifest = json.loads((root / 'docs/brand/ASSET_MANIFEST.json').read_text())
    assert manifest['approval'] == 'owner-approved'
    assert manifest['source_pdf_sha256'] == 'f96761f6422339fc8b7b5dc09d3d935a7dc76dc9f0840e317b37f9eca9781bc2'
    for item in manifest['assets']:
        path = Path(item['path'])
        assert not path.is_absolute() and '..' not in path.parts
        source = root / path
        assert not source.is_symlink()
        b = source.read_bytes()
        assert len(b) == item['bytes'] and hashlib.sha256(b).hexdigest() == item['sha256'], str(path)
        if source.suffix == '.xml': ET.fromstring(b)
        if source.suffix == '.svg':
            xml = ET.fromstring(b)
            assert not any(e.tag.endswith(('image', 'text', 'script', 'foreignObject')) for e in xml.iter())
            assert b'data:image' not in b and b'http://' not in b.replace(b'http://www.w3.org/2000/svg', b'')
    measurements = json.loads((root / 'docs/brand/MEASUREMENTS.json').read_text())
    assert measurements['mark_components'] == 5 and measurements['word_components'] == 8
    assert measurements['mark_contour_overlap'] > .995 and measurements['word_contour_overlap'] > .995
    assert measurements['adaptive_max_radius_dp'] <= 33
    for density, size in [('mdpi', 48), ('hdpi', 72), ('xhdpi', 96), ('xxhdpi', 144), ('xxxhdpi', 192)]:
        b = (root / f'mobile_app/android/app/src/main/res/mipmap-{density}/ic_launcher.png').read_bytes()
        assert b[:8] == b'\x89PNG\r\n\x1a\n' and struct.unpack('>II', b[16:24]) == (size, size)
    ios = root / 'mobile_app/ios/Runner/Assets.xcassets/AppIcon.appiconset'
    for item in json.loads((ios / 'Contents.json').read_text())['images']:
        if 'filename' not in item: continue
        b = (ios / item['filename']).read_bytes()
        size = round(float(item['size'].split('x')[0]) * float(item['scale'][:-1]))
        assert struct.unpack('>II', b[16:24]) == (size, size) and b[25] == 2
    android = root / 'mobile_app/android/app/src/main/res'
    assert 'monochrome' in (android / 'mipmap-anydpi-v33/ic_launcher.xml').read_text()
    for qualifier in ['values-v31', 'values-night-v31']:
        assert 'windowSplashScreenAnimatedIcon' in (android / qualifier / 'styles.xml').read_text()
    geometry = root / 'backend-api-runtime/resources/brand/aqer-approved.json'
    config = (root / 'backend-api-runtime/config/listing_media.php').read_text()
    assert hashlib.sha256(geometry.read_bytes()).hexdigest() in config
    assert "env('LISTING_WATERMARK_ENABLED',false)" in config
    assert '    - assets/brand/' in (root / 'mobile_app/pubspec.yaml').read_text()
    return len(manifest['assets'])


if __name__ == '__main__':
    print(f'Verified {verify()} approved brand exports, Android masks, source contours and opt-in watermark pin.')
