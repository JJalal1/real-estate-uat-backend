"""Only known Home diagnostics are excluded, never admitted as editor proof."""
import ast
import hashlib
from pathlib import Path
import sys
import unittest

HERE=Path(__file__).resolve().parent
ADAPTER=HERE.parent/'adapter'
if not (ADAPTER/'ci_remote_evidence.py').is_file():ADAPTER=HERE.parent/'integration-adapter-fix5-home'
sys.path.insert(0,str(ADAPTER))
import controller as module
import test_controller as scaffold


class HomeDiagnosticTests(unittest.TestCase):
    def setUp(self):
        self.base=scaffold.ControllerTests(methodName='test_snapshot_is_read_only_no_general_phase_calls_and_wire_frame_list')
        self.base.setUp();self.base.initial()
        self.controller,self.probe=self.base.controller,self.base.probe
    def tearDown(self):self.base.tearDown()
    def home(self,name='C1-before-add-home.png'):
        data=b'SYNTHETIC_PRIVATE_HOME_DIAGNOSTIC_ONLY'
        file=self.probe.out/name;file.write_bytes(data);file.chmod(0o600)
        record={'file':name,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest(),'width':540,'height':960,
            'capture':'official_emulator_console_host_png','authenticated_editor_only':False,
            'authenticated_broker_home_only':True,'capture_scope':module.HOME_DIAGNOSTIC_SCOPE,
            'privacy_before_and_after':True,'home_binding_unchanged':True}
        self.probe.report['frames'].append(record)
        return record

    def test_known_diagnostics_remain_private_and_are_excluded_from_c1_acceptance(self):
        names=['C1-before-add-home.png','C1-restore-before-add-home.png']
        for name in names:self.home(name)
        snapshot=self.controller.snapshot()
        selected={row['file'] for row in snapshot['evidence']}
        self.assertFalse(selected&set(names))
        self.assertTrue({'C1-restored-title.png','C1-restored-complete-photo.png',
                         'C1-create-photo.webm','C1-restored-facts.webm'}<=selected)
        self.assertTrue(all((self.probe.out/name).exists() for name in names))
        self.assertEqual(len(self.probe.report['frames']),4)

    def test_media_policy_still_rejects_even_well_formed_home_diagnostic(self):
        record=self.home()
        with self.assertRaisesRegex(module.ControllerRefused,'^actual_safe_capture_predicate_required$'):
            self.controller._media([record['file']])

    def test_malformed_known_home_is_never_silently_discarded_or_relabelled(self):
        record=self.home()
        for change in [{'authenticated_editor_only':True},{'capture_scope':'other'},
                       {'privacy_before_and_after':False},{'home_binding_unchanged':False},
                       {'capture':'android_guest_screencap'},{'width':541},{'bytes':True},{'sha256':'bad'}]:
            with self.subTest(change=change):
                original=dict(record);record.update(change)
                with self.assertRaisesRegex(module.ControllerRefused,'^malformed_home_diagnostic_not_acceptance_media$'):
                    self.controller.snapshot()
                record.clear();record.update(original)
        record['unknown_extra']=True
        with self.assertRaises(module.ControllerRefused):self.controller.snapshot()

    def test_missing_proof_flag_unknown_home_name_and_duplicates_refuse(self):
        record=self.home()
        del record['authenticated_broker_home_only']
        with self.assertRaises(module.ControllerRefused):self.controller.snapshot()
        record['authenticated_broker_home_only']=True
        record['file']='C1-unknown-home.png'
        with self.assertRaises(module.ControllerRefused):self.controller.snapshot()
        record['file']='C1-before-add-home.png'
        self.probe.report['frames'].append(dict(record))
        with self.assertRaises(module.ControllerRefused):self.controller.snapshot()

    def test_unknown_noneditor_extra_still_uses_existing_strict_media_refusal(self):
        record=self.home('C1-unknown-home.png')
        record.pop('capture_scope');record.pop('authenticated_broker_home_only')
        with self.assertRaisesRegex(module.ControllerRefused,'^actual_safe_capture_predicate_required$'):
            self.controller.snapshot()

    def test_media_function_source_is_byte_identical_to_frozen_controller(self):
        source=(HERE/'controller.py').read_text();tree=ast.parse(source)
        controller=next(n for n in tree.body if isinstance(n,ast.ClassDef) and n.name=='Controller')
        method=next(n for n in controller.body if isinstance(n,ast.FunctionDef) and n.name=='_media')
        self.assertEqual(hashlib.sha256(ast.get_source_segment(source,method).encode()).hexdigest(),
                         'adb99b63ecba4d39804d3bdaf02e05a9d79f077be6c9d462fcda491ce0be048e')


if __name__=='__main__':unittest.main()
