"""Safety boundary checks for the separately compiled synthetic visual target.

These checks do not claim Dart compilation, native screenshots, or live auth.
"""
from pathlib import Path
import re
import unittest


ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "scripts/phase23_offline_visual_main.dart"


class OfflineVisualContract(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.source = SOURCE.read_text()

    def test_target_is_separate_and_explicitly_opted_in(self):
        self.assertIn("bool.fromEnvironment('AQER_OFFLINE_VISUAL_QA')", self.source)
        self.assertIn("if (!_enabled) throw StateError", self.source)
        self.assertIn("AQER_OFFLINE_VISUAL_TARGET_V1", self.source)
        self.assertNotIn("/main.dart'", self.source)
        self.assertEqual(SOURCE.relative_to(ROOT).parts[0], 'scripts')

    def test_no_live_configuration_or_secret_input(self):
        for forbidden in ('onrender.com', 'supabase.co', 'Firebase', 'String.fromEnvironment',
                          'Platform.environment', 'SecureSessionStore', 'Bearer ',
                          'IOHttpClientAdapter', 'DefaultHttpClientAdapter'):
            self.assertNotIn(forbidden, self.source)
        urls = re.findall(r'https?://[^\s\'"<>]+', self.source)
        self.assertEqual(set(urls), {'https://synthetic.invalid'})

    def test_all_dio_io_and_direct_dart_network_fail_closed(self):
        for guard in ("HttpOverrides.global = _NoNetwork()", "throw const SocketException",
                      "dio.httpClientAdapter = adapter", "options.method != 'GET'",
                      "options.uri.host != 'synthetic.invalid'", 'options.uri.hasPort',
                      '!visualCase.paths.contains(options.path)', 'options.data != null',
                      "key.toLowerCase() == 'authorization'", "_failure('unapproved_request')"):
            self.assertIn(guard, self.source)
        self.assertNotIn('super.createHttpClient', self.source)

    def test_matrix_is_bounded_and_has_all_four_visual_states(self):
        block = self.source.split('const _cases = <_VisualCase>[')[1].split('];')[0]
        rows = re.findall(r"_VisualCase\('([^']+)', '([^']+)', '([^']+)', (true|false), (1|2\.4)\)", block)
        self.assertEqual(len(rows), 14)
        self.assertEqual({r[1] for r in rows}, {'regular', 'broker', 'support'})
        self.assertEqual({r[2] for r in rows}, {'populated', 'empty', 'error', 'loading'})
        for surface in ('favorites', 'support'):
            self.assertEqual({r[2] for r in rows if r[0] == surface},
                             {'populated', 'empty', 'error', 'loading'})
        self.assertEqual({r[3] for r in rows}, {'true', 'false'})
        self.assertEqual({r[4] for r in rows}, {'1', '2.4'})

    def test_native_collector_handshake_and_failure_are_explicit(self):
        for marker in ('SYNTHETIC OFFLINE', 'AQER_VISUAL_CASE_', 'AQER_VISUAL_NEXT',
                       'AQER_VISUAL_FAILURE', "'event': 'failure'", "'event': 'ready'",
                       "'case': current.index", "'failures': _failures.value",
                       "_failure('fixture_request_missing')"):
            self.assertIn(marker, self.source)
        self.assertIn('AbsorbPointer(child: KeyedSubtree(', self.source)

    def test_only_outer_vertical_scrolling_can_reach_private_content(self):
        for boundary in ("label: 'AQER_VISUAL_SCROLL'", 'onScrollDown:', 'onScrollUp:',
                         'onVerticalDragUpdate:', 'excludeFromSemantics: true',
                         'AbsorbPointer(child: KeyedSubtree(', 'position.jumpTo(offset)',
                         'candidate.hasContentDimensions',
                         '.clamp(position.minScrollExtent, position.maxScrollExtent)'):
            self.assertIn(boundary, self.source)
        body = self.source.split('// Only this outer vertical gesture/semantic action')[1]
        self.assertNotIn('onTap:', body)
        self.assertNotIn('onHorizontalDrag', body)

    def test_actual_widgets_themes_and_rtl_are_reused(self):
        for component in ('FavoritesScreen()', 'BrokerAvailabilityScreen()',
                          'BrokerCustomersScreen()', 'MessagesScreen()',
                          'SupportAdminScreen()', 'NotificationsScreen()',
                          'ConversationReportsScreen()', 'AppTheme.light', 'AppTheme.dark',
                          'GlobalMaterialLocalizations.delegate', 'TextDirection.rtl'):
            self.assertIn(component, self.source)


if __name__ == '__main__':
    unittest.main()
