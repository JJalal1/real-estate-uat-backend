"""A failed live fixture must retain honest diagnostics, never become a pass."""
import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

SPEC = importlib.util.spec_from_file_location('probe_images', Path(__file__).parents[1] / 'probe_adaptive_images.py')
probe = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(probe)


class ProbeEvidenceTest(unittest.TestCase):
    def run_probe(self, reader, fail=False):
        with tempfile.TemporaryDirectory() as folder:
            previous = os.getcwd()
            try:
                os.chdir(folder)
                output = Path(folder) / 'metrics.json'
                with patch.object(probe, 'read', side_effect=reader), patch('sys.argv', ['probe', '--output', str(output)]), patch('builtins.print'):
                    if fail:
                        with self.assertRaisesRegex(AssertionError, 'Synthetic fixture 60 returned 404'):
                            probe.main()
                    else:
                        probe.main()
                return json.loads(output.read_text())
            finally:
                os.chdir(previous)

    def test_404_is_a_failure_with_persisted_metadata_and_no_body(self):
        def read(url, **kwargs):
            return b'private body must never be saved', {'status': 200 if url.endswith('/health') else 404, 'bytes': 31, 'elapsed_ms': 90}
        result = self.run_probe(read, fail=True)
        self.assertFalse(result['completed'])
        self.assertEqual(result['error_type'], 'AssertionError')
        self.assertEqual(result['fixture_lookups'][0]['status'], 404)
        self.assertEqual(result['fixture_lookups'][0]['fixture_property_id'], 60)
        self.assertEqual(result['samples'], [])
        self.assertNotIn('private body', json.dumps(result))

    def test_all_original_byte_and_privacy_conditions_still_pass(self):
        def read(url, rate=0, headers=None):
            if url.endswith('/health'):
                return b'{}', {'status': 200}
            if '/properties/' in url:
                return json.dumps({'data': {'status': 'published', 'images': [{'url': probe.ORIGIN + '/api/property-media/fixture?v=v2-wm-bf7611483e0689ad9ccd'}]}}).encode(), {'status': 200}
            name = dict(probe.urllib.parse.parse_qsl(probe.urllib.parse.urlsplit(url).query))['variant']
            if name == 'original':
                return b'', {'status': 422}
            if headers:
                return b'', {'status': 304, 'bytes': 0}
            body = b'\xff\xd8' + b'x' * {'gallery': 120, 'card': 60, 'thumb': 20}[name] + b'\xff\xd9'
            return body, {'status': 200, 'bytes': len(body), 'etag': 'synthetic-etag', 'variant': name}
        result = self.run_probe(read)
        self.assertTrue(result['completed'])
        self.assertEqual(len(result['samples']), 3)
        self.assertTrue(result['adaptive_available'])
        self.assertGreater(result['detail_saving_percent'], 0)
        self.assertTrue(all(row['original_variant']['status'] == 422 for row in result['samples']))


if __name__ == '__main__':
    unittest.main()
