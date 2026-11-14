"""Boundaries of the isolated target; not Android/device acceptance itself."""
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'scripts/phase23_offline_device_main.dart'


class OfflineDeviceContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SOURCE.read_text()

    def test_separate_explicit_target_and_honest_network_scope(self):
        self.assertIn("bool.fromEnvironment('AQER_OFFLINE_DEVICE_QA')", self.source)
        self.assertIn("if (!_enabled) throw StateError", self.source)
        self.assertIn('AQER_OFFLINE_DEVICE_TARGET_V1', self.source)
        self.assertIn('SYNTHETIC DEVICE SESSION', self.source)
        self.assertIn('Native map/device network', self.source)
        self.assertEqual(SOURCE.relative_to(ROOT).parts[0], 'scripts')
        self.assertNotIn("/main.dart'", self.source)

    def test_no_real_credentials_or_business_transport(self):
        for forbidden in ('onrender.com', 'supabase.co', 'Firebase', 'String.fromEnvironment',
                          'Platform.environment', 'Bearer ', 'IOHttpClientAdapter',
                          'DefaultHttpClientAdapter', 'super.createHttpClient'):
            self.assertNotIn(forbidden, self.source)
        urls = re.findall(r'https?://[^\s\'"<>]+', self.source)
        self.assertEqual(set(urls), {'https://synthetic.invalid'})
        for guard in ("HttpOverrides.global = _NoDartNetwork()", 'throw const SocketException',
                      'dio.httpClientAdapter = _StatusOnlyAdapter(media)',
                      "options.uri.host == 'synthetic.invalid'", '!options.uri.hasPort',
                      "options.method == 'GET'", "options.path == '/account-verification'",
                      'options.data == null', 'options.queryParameters.isEmpty',
                      "key.toLowerCase() == 'authorization'", 'DEVICE_TARGET_API_FORBIDDEN'):
            self.assertIn(guard, self.source)

    def test_real_widgets_and_platform_providers_are_never_replaced(self):
        for actual in ('const AssistedSearchScreen()',
                       'const PropertyLocationPickerScreen(reverseLookup: null)',
                       "const AccountVerificationScreen(initialType: 'owner')"):
            self.assertIn(actual, self.source)
        overrides = re.findall(r'(\w+Provider)\.override\w+', self.source)
        self.assertEqual(set(overrides), {'authControllerProvider', 'authRepositoryProvider', 'dioProvider'})
        for fake in ('setMockMethodCallHandler', 'setMethodCallHandler', 'Wave3VoiceFake',
                     'VoiceEvent(', 'Completer<PropertyLocationSelection>', 'DEVICE_GPS',
                     'propertyCurrentLocationProvider.override', 'voiceInputProvider.override'):
            self.assertNotIn(fake, self.source)

    def test_gps_receipt_only_comes_from_product_navigator_result(self):
        block = self.source.split('if (kind == 2 && result is PropertyLocationSelection)')[1].split('}')[0]
        for fact in ('result.method', 'result.latitude', 'result.longitude', 'result.accuracyMetres'):
            self.assertIn(fact, block)
        self.assertNotIn('15.3729', self.source)
        self.assertNotIn('44.2051', self.source)
        self.assertIn('await _navigator.currentState!.push<Object?>', self.source)

    def test_observation_never_injects_voice_or_calls_product_controls(self):
        block = self.source.split('void _observeWidgets()')[1].split('Future<void> _snapshot()')[0]
        for actual in ('widget.capture', 'capture.phase.index', 'capture.permissionDenied',
                       'capture.transcript.length', 'capture.preview.length', 'widget.onPressed != null'):
            self.assertIn(actual, block)
        for mutation in ('.start(', '.stop(', '.cancel(', '.onPressed!(', '.onTap!(',
                         'capture.phase =', 'capture.transcript =', 'capture.preview ='):
            self.assertNotIn(mutation, block)
        self.assertNotRegex(block, r'\.text\s*=(?!=)')

    def test_media_evidence_reads_only_bounded_native_temporary_files(self):
        for guard in ('getTemporaryDirectory()', "/stage5_uploads'", 'followLinks: false',
                      'entry is! File', 'if (++count > 4)', '8 * 1024 * 1024',
                      'ui.instantiateImageCodec(await entry.readAsBytes(), targetWidth: 64)',
                      'frame.image.dispose(); codec.dispose();'):
            self.assertIn(guard, self.source)
        for forbidden in ('writeAsBytes', 'writeAsString', 'deleteSync', 'Directory.systemTemp'):
            self.assertNotIn(forbidden, self.source)

    def test_metadata_is_closed_numeric_and_contains_no_user_content(self):
        block = self.source.split('final _meta = <String, int>{')[1].split('};')[0]
        keys = re.findall(r"'([A-Za-z0-9]+)'\s*:\s*[0-9]+", block)
        self.assertEqual(len(keys), 29)
        self.assertIn("debugPrint('AQER_DEVICE $payload')", self.source)
        self.assertIn("label: 'DEVICE_META ${jsonEncode(_meta)}'", self.source)
        for private in ('token', 'phone', 'name', 'email', 'text', 'path'):
            self.assertNotIn(private, keys)

    def test_snapshot_acknowledges_completed_media_inspection(self):
        block = self.source.split('Future<void> _snapshot()')[1].split('Widget _control')[0]
        self.assertLess(block.index("_meta['mediaDecodable'] = decoded"),
                        block.index("_meta['snapshotSeq'] = _meta['snapshotSeq']! + 1"))
        tail = block.split('finally {')[1]
        self.assertLess(tail.index("_meta['snapshotSeq']"), tail.index('_publish(force: true)'))

    def test_route_semantics_cannot_hide_persistent_harness_controls(self):
        self.assertIn('Expanded(child: Semantics(container: true, explicitChildNodes: true, child: child!))',
                      self.source)

    def test_header_and_controls_have_distinct_semantic_boundaries(self):
        # Native RTL Android wrapped the LTR header in bidi controls and merged
        # its labels into a full-screen node. Keep each control/meta independent.
        self.assertIn('SafeArea(bottom: false, child: Semantics(container: true, explicitChildNodes: true,',
                      self.source)
        self.assertIn('container: true, label: label, button: true, excludeSemantics: true, onTap: action,',
                      self.source)
        self.assertIn("Semantics(container: true, label: 'DEVICE_META ${jsonEncode(_meta)}'",
                      self.source)


if __name__ == '__main__':
    unittest.main()
