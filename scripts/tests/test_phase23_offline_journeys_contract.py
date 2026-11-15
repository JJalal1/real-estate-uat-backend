"""Boundaries of the separate native journey entry; not native run evidence."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / 'scripts/phase23_offline_journeys_main.dart'


class OfflineJourneysContract(unittest.TestCase):
    def test_tail_mode_starts_nine_without_seeding_or_replaying_history(self):
        source=(Path(__file__).resolve().parents[1]/'phase23_offline_journeys_main.dart').read_text()
        self.assertIn("bool.fromEnvironment('AQER_OFFLINE_JOURNEYS_TAIL_ONLY')",source)
        self.assertIn('var stage = _tailOnly ? 9 : 0',source)
        self.assertIn('TAIL_JOURNEY_REQUIRES_FRESH_SYNTHETIC_STATE',source)
        self.assertIn('AQER_OFFLINE_JOURNEYS_TAIL9_V1',source)
        workflow=(Path(__file__).resolve().parents[2]/'.github/workflows/phase23-offline-journeys.yml').read_text()
        self.assertIn("PHASE23_JOURNEYS_TAIL_ONLY: 'true'",workflow)
        self.assertIn('--dart-define=AQER_OFFLINE_JOURNEYS_TAIL_ONLY=true',workflow)

    def test_harness_header_and_next_are_independent_semantics_boundaries(self):
        source=(Path(__file__).resolve().parents[1]/'phase23_offline_journeys_main.dart').read_text()
        self.assertIn('Semantics(container: true, explicitChildNodes: true,\n              child: MediaQuery.withNoTextScaling',source)
        self.assertIn("Semantics(container: true, label: 'AQER_JOURNEY_NEXT'",source)

    @classmethod
    def setUpClass(cls):
        cls.source = SOURCE.read_text()

    def test_target_is_separate_and_explicit(self):
        for marker in ("bool.fromEnvironment('AQER_OFFLINE_JOURNEYS_QA')",
                       'if (!_enabled) throw StateError',
                       'AQER_OFFLINE_JOURNEYS_TARGET_V1', 'SYNTHETIC OFFLINE',
                       'AQER_JOURNEY_STAGE_', 'AQER_JOURNEY_NEXT',
                       'AQER_JOURNEY_FAILURE', "debugPrint('AQER_JOURNEY "):
            self.assertIn(marker, self.source)
        self.assertNotIn("/main.dart'", self.source)

    def test_no_live_configuration_credentials_or_socket_fallback(self):
        for forbidden in ('onrender.com', 'supabase.co', 'Firebase', 'String.fromEnvironment',
                          'Platform.environment', 'SecureSessionStore', 'Bearer ',
                          'IOHttpClientAdapter', 'DefaultHttpClientAdapter', 'super.createHttpClient'):
            self.assertNotIn(forbidden, self.source)
        self.assertEqual(set(re.findall(r'https?://[^\s\'"<>]+', self.source)),
                         {'https://synthetic.invalid'})
        for guard in ('HttpOverrides.global = _NoNetwork()', 'throw const SocketException',
                      'dio.httpClientAdapter = adapter', "options.method != 'GET'",
                      "options.uri.host != 'synthetic.invalid'", 'options.uri.hasPort',
                      '!paths.contains(options.path)', 'options.data != null',
                      "key.toLowerCase() == 'authorization'", "_failure('unapproved_request')"):
            self.assertIn(guard, self.source)

    def test_real_history_is_read_and_never_seeded_or_overridden(self):
        self.assertIn('container.read(recentPropertiesStoreProvider).load()', self.source)
        self.assertIn("'recent_ids': rows.map((row) => row.id)", self.source)
        self.assertIn('await history.exists()', self.source)
        self.assertIn('await history.length()', self.source)
        for forbidden in ('recentPropertiesStoreProvider.override',
                          'recentPropertiesProvider.override', 'recentHistoryDirectoryProvider.override',
                          '.record(', '.clear(', 'history.write', 'history.delete',
                          'PropertyDetailsScreen('):
            self.assertNotIn(forbidden, self.source)
        self.assertEqual(len(re.findall(r'\.writeAsString\(', self.source)), 2)
        self.assertIn('await control.writeAsString(', self.source)
        self.assertIn('await journey.control.writeAsString(', self.source)

    def test_real_router_owns_details_and_role_tabs(self):
        for expected in ('container.read(appRouterProvider)', 'MaterialApp.router(',
                         'routerConfig: journey.router', "journey.router.go('/properties/9001')",
                         "journey.router.go('/properties/9002')", "journey.router.go('/recent')",
                         'journey.adapter.workspaceRequests == 0',
                         "_hasActualText('لوحة الدلال')",
                         "_hasActualText('أدوات الدلال بعد اعتماد التوثيق')"):
            self.assertIn(expected, self.source)
        for forbidden in ('AppShellScreen(', 'RecentPropertiesScreen(', 'BrokerDashboardScreen(',
                          'Stage6AuthGate(', 'NavigationBar(', 'BottomNavigationBar('):
            self.assertNotIn(forbidden, self.source)
        # The target neither recreates a shell nor selects its private tab state.
        self.assertNotIn('_selectTab', self.source)

    def test_scope_and_restart_protocol_are_bounded(self):
        scopes = self.source.split('const _scopes = <String>[')[1].split('];')[0]
        self.assertEqual(re.findall(r"'([^']+)'", scopes),
                         ['A'] * 6 + ['B', 'guest', 'A', 'verified', 'verified', 'pending', 'pending', 'A', 'A', 'A'])
        for guard in ("raw['stage'] != 4", "raw['restart_count'] != 0", 'stage = 5;',
                      'restarts = 1;', 'journey.stage == 4 || journey.stage == 13',
                      "'restart_count': restartCount", "'requests': adapter.requests",
                      "'file_exists': exists", "'file_bytes': exists ? await history.length() : 0"):
            self.assertIn(guard, self.source)

    def test_no_remote_view_or_map_side_effects(self):
        self.assertIn("'is_owner': true", self.source)
        self.assertIn("homeLocationAttemptedProvider.overrideWith((ref) => true)", self.source)
        self.assertNotIn("'latitude':", self.source)
        self.assertNotIn("'longitude':", self.source)
        paths = self.source.split('static const paths = <String>{')[1].split('};')[0]
        self.assertNotIn('/view', paths)
        self.assertNotIn('/tiles', paths)

    def test_native_thread_link_is_observed_without_target_navigation(self):
        for proof in ('routeInformationProvider.addListener(_observeNativeRoute)',
                      "routeInformationProvider.value.uri.path != '/messages/9010'",
                      'journey.stage = 14', 'journey.adapter.threadRequests == 0',
                      "_hasActualText('محادثة اصطناعية للاختبار')",
                      "path == '/messages/threads/9010'"):
            self.assertIn(proof, self.source)
        for navigation in re.findall(r'\.(?:go|push|replace)\(([^\n]+)', self.source):
            self.assertNotIn('messages', navigation)

    def test_final_favorites_supplement_uses_real_route_and_vertical_only_scroll(self):
        for boundary in ("journey.router.go('/favorites')", "path == '/favorites'",
                         "'AQER_JOURNEY_SCROLL'", 'journey.stage == 15 ? AppTheme.dark : AppTheme.light',
                         'textScaler: const TextScaler.linear(1)',
                         'AbsorbPointer(absorbing: journey.stage == 15',
                         'onVerticalDragUpdate:', 'position.jumpTo(',
                         'candidate.pixels < candidate.maxScrollExtent - .5'):
            self.assertIn(boundary, self.source)
        self.assertNotIn('FavoritesScreen(', self.source)


if __name__ == '__main__':
    unittest.main()
