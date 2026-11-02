import importlib.util
from pathlib import Path
import unittest

SPEC = importlib.util.spec_from_file_location('release_graph', Path(__file__).parents[1] / 'verify_phase1_release_test_graph.py')
graph = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(graph)


class ReleaseTestGraphTest(unittest.TestCase):
    def test_only_the_ordered_uat_release_pair_can_pass(self):
        valid = (':app:stripUatReleaseDebugSymbols SKIPPED\n'
                 ':app:mergeUatReleaseNativeDebugMetadata SKIPPED\n'
                 ':app:assembleUatRelease SKIPPED\n:app:assembleUatReleaseAndroidTest SKIPPED\n')
        self.assertEqual('release_then_tests', graph.validate_graph(valid)['order'])
        for invalid in ['', ':app:assembleUatRelease SKIPPED', '\n'.join(reversed(valid.splitlines())),
                        valid + ':app:assembleUatDebug SKIPPED\n',
                        valid + ':shared_preferences_android:compileDebugJavaWithJavac SKIPPED\n',
                        valid + ':app:assembleProductionRelease SKIPPED\n', valid + valid]:
            with self.subTest(graph=invalid), self.assertRaises(ValueError):
                graph.validate_graph(invalid)
