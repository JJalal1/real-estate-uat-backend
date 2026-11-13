import json
from pathlib import Path
import sys
import unittest
sys.path.insert(0,str(Path(__file__).parents[1]))
from phase23_callback_metadata import FIELDS,safe_callback_label
from run_phase23_native import NativeRun

class CallbackMetadataPrivacy(unittest.TestCase):
    def test_only_known_controls_and_bounded_numeric_schema_are_exported(self):
        value={k:0 for k in FIELDS};value.update(v=1,actor=2)
        raw='CB-META:'+json.dumps(value)
        self.assertIsNotNone(safe_callback_label(raw))
        for changes in [{'token':'private'},{'v':2},{'errors':False},{'actor':66},{'bEpoch':100001},{'bEpoch':-2}]:
            candidate=dict(value,**changes)
            self.assertIsNone(safe_callback_label('CB-META:'+json.dumps(candidate)))
        self.assertIsNone(safe_callback_label('CB-META:'+json.dumps({'v':1})))
        self.assertIsNone(safe_callback_label('CB-META:invalid'))
        self.assertIsNone(safe_callback_label('CB arbitrary private task'))

    def test_unverified_product_cannot_export_harness_text(self):
        rows=[{'text':'CB controls'},{'text':'CB AI PASS'},{'text':'PRIVATE PERSON'}]
        controls,protected=NativeRun.private_ui_controls(rows,force_private=True)
        self.assertEqual(controls,[]);self.assertTrue(protected)
        controls,protected=NativeRun.private_ui_controls(rows,callback_harness=True)
        self.assertTrue(protected)
        self.assertEqual({x['description'] for x in controls},{'CB controls','CB AI PASS'})
        self.assertNotIn('PRIVATE PERSON',str(controls))

    def test_default_entrypoint_does_not_reference_the_alternate_target(self):
        root=Path(__file__).parents[2]
        self.assertNotIn('phase23_native_callback_main',(root/'mobile_app/lib/main.dart').read_text())
        workflow=(root/'.github/workflows/phase23-native-callbacks.yml').read_text()
        self.assertIn("contains(github.event.head_commit.message, '[run-callbacks]')",workflow)
        self.assertIn('--target lib/phase23_native_callback_main.dart',workflow)
        self.assertIn('--dart-define=AQER_PHASE23_CALLBACK_HARNESS=true',workflow)
