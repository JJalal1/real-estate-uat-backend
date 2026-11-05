"""Synthetic logout postconditions only; no native/account/API acceptance."""
import ast
import hashlib
import importlib.util
import json
from pathlib import Path
import sys
import unittest

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
ROLE_PATH = 'C2_SOURCE_PROPOSAL/c2_native_roles.py'
PREVIOUS_UNCHANGED = {
    'variants/ROOT_C4_EXECUTOR/phase_extensions.py': '9832c9943e0d83f7e3fc3591b022bd26471caf0f3c6a0b6e31f0fbc8a5437240',
    'variants/ROOT_C2_EXECUTOR_V2/phase_extensions.py': '0338fd80c96908d54b8732861f2c50a810f13f73381912e34591e33e16588e51',
    'variants/ROOT_C2_EXECUTOR_V2/root_extension_dispatch.py': '309f69d2939342684f870b68b3dee2a216c07e836de07a4951640a4307a53516',
    'variants/LOCAL_REMAINING_PROPOSAL/local_stage_policy.py': '2a54658205998dbb02f2a0a3f4c59597d348125d0b520402e19ba8ef85527ec2',
    'variants/promoted_cleanup.py': '4a7752b29cc8b1417e5d82ab94c9113e3687b6b6e37ba995847e387f5d262f67',
    'variants/runtime/host_console_capture.py': '2ec10b2659ea3f073c47d02c1800cd49b35b58e51ce8430517af74a1ecadcafa',
    'variants/ci_remote_evidence.py': 'c481b8b4c2556f27e16fc687858f8d7212789fa27cad372acd975754c459e2f7',
    # The separate Fix5 Home mixin factory delta is fenced by test_home_capture.
    'ci_remote_evidence.py': 'c481b8b4c2556f27e16fc687858f8d7212789fa27cad372acd975754c459e2f7',
}


def load_roles():
    spec = importlib.util.spec_from_file_location('_logout_home_roles', HERE / 'variants' / ROLE_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class Clock:
    def __init__(self): self.value = 0
    def monotonic(self): return self.value
    def sleep(self, seconds): self.value += seconds


def row(label='', *, hint='', visible=True, package='com.aqer.yemen.uat'):
    return {'text': label, 'description': '', 'hint': hint, 'visible': visible, 'package': package}


def home(module, *, anchor='ماذا تبحث عنه؟', hint=False, footer=None):
    result = [row(label) for label in (module.GUEST_HOME_NAV if footer is None else footer)]
    result.append(row(hint=anchor) if hint else row(anchor))
    return result


class FakeProbe:
    def __init__(self, module, role='regular', frames=None):
        self.module, self.role = module, role
        self.active_native_role, self.authenticated = role, True
        self.native_auth_uncertain, self.recorder = False, None
        self.report, self.events = {}, []
        self.stage, self.reads = 'account', 0
        self.frames = frames if frames is not None else [home(module)]
        self.guest_rows = [row('تسجيل الدخول أو إنشاء حساب')]
        self.expire_after_home = False
        self.read_error = None
        self.adapter = object()
        self.retained_rows = [row(label) for label in module.ROLE_NAV['broker']]
        self.startup_error = None
        self.support_queue_rows = [row(label) for label in ('تحقيق الإعلانات','طلبات التحقيق','رجوع')]
        self.support_shell_rows = [row(label) for label in module.ROLE_NAV['support']]
    def tap(self, label, seek=True):
        if self.authenticated:
            raise AssertionError('logout actions must remain count-only')
        self.events.append(('tap', label))
        if label == 'تسجيل الخروج':
            if self.stage != 'account': raise AssertionError('duplicate logout')
            self.stage = 'after_logout'
        elif label == 'حسابي':
            if self.stage == 'after_logout':
                if self.expire_after_home: raise RuntimeError('SYNTHETIC_SIGNED_DEADLINE_EXPIRED')
                self.stage = 'guest_account'
            elif self.stage in {'broker_home','support_shell'}: self.stage = 'account'
            elif self.stage != 'account': raise AssertionError('duplicate Account tap')
        elif label == 'رجوع':
            if self.stage != 'support_queue' or self.role != 'support':
                raise AssertionError('only observed support queue Back')
            self.stage = 'support_shell'
        else:
            raise AssertionError('no reauthentication or alternate navigation')
        self.report['auth_input_operations_delivered'] = self.report.get('auth_input_operations_delivered', 0) + 1
    def nodes(self):
        self.events.append(('read', self.stage))
        if self.read_error is not None: raise RuntimeError(self.read_error)
        if self.stage == 'after_logout':
            result = self.frames[min(self.reads, len(self.frames)-1)]
            self.reads += 1
            return result
        if self.stage == 'guest_account': return self.guest_rows
        if self.stage == 'broker_home': return self.retained_rows
        if self.stage == 'support_queue': return self.support_queue_rows
        if self.stage == 'support_shell' or self.stage == 'account' and self.role == 'support':
            return self.support_shell_rows
        return [row('تسجيل الخروج')]
    def wait(self, label, seconds):
        # Source wait is read-only. Deliberately allow it to return so the
        # final explicit visible APP Login/noLogout/noAUTH predicate is tested.
        self.events.append(('wait', label))
        if label == 'لوحة الدعم' and self.stage == 'support_shell': return
        if self.stage != 'guest_account': raise AssertionError('Login wait before observed Home then Account')
    def save(self):
        encoded = json.dumps(self.report)
        if 'SYNTHETIC_PRIVATE_ERROR' in encoded: raise AssertionError('raw exception exported')
    def safe_capture(self, *args): raise AssertionError('no image capture')
    def record_start(self, *args): raise AssertionError('no video capture')
    def set(self, *args): raise AssertionError('no credential input')
    def stop_session(self, reason):
        if self.role != 'broker' or self.authenticated: raise AssertionError('broker count-only lifecycle')
        self.events.append(('lifecycle', 'close'))
        self.adapter = None
    def adb(self, *args):
        if self.role != 'broker' or self.authenticated or self.adapter is not None:
            raise AssertionError('broker count-only closed admission required')
        if args != ('shell','am','force-stop',self.module.APP): raise AssertionError('no arbitrary raw transport')
        self.events.append(('lifecycle', 'force-stop'))
    def startup(self):
        if self.role != 'broker' or self.authenticated: raise AssertionError('broker count-only lifecycle')
        self.events.append(('lifecycle', 'startup'))
        if self.startup_error: raise RuntimeError(self.startup_error)
        self.adapter = object()
        self.stage = 'broker_home'
    def instrument(self, *args, **kwargs): raise AssertionError('only ordinary probe taps')


class LogoutHomeTests(unittest.TestCase):
    def setUp(self):
        self.module = load_roles()
        self.module.time = Clock()
    def taps(self, probe): return [label for kind,label in probe.events if kind == 'tap']
    def blocked(self, frames, *, role='regular'):
        probe = FakeProbe(self.module, role, frames)
        receipt = self.module.native_logout_role(probe)
        self.assertEqual(receipt['status'], 'BLOCKED')
        self.assertEqual(receipt['reason'], 'native_guest_marketplace_not_observed')
        self.assertEqual(self.taps(probe), ['حسابي','تسجيل الخروج'])
        self.assertTrue(probe.native_auth_uncertain)
        self.assertEqual(probe.active_native_role,role)
        self.assertFalse(probe.authenticated)
        return probe

    def test_all_three_roles_observe_home_then_one_account_and_guest_gate(self):
        for role in self.module.KNOWN_ROLES:
            for anchor in self.module.GUEST_HOME_ANCHORS:
                with self.subTest(role=role,anchor=anchor):
                    probe=FakeProbe(self.module,role,[home(self.module,anchor=anchor,hint=anchor.startswith('ابحث'))])
                    receipt=self.module.native_logout_role(probe)
                    self.assertEqual(receipt['status'],'PASS_WITHIN_LOGOUT_UI_SCOPE')
                    self.assertEqual(self.taps(probe),['حسابي','تسجيل الخروج','حسابي'])
                    self.assertEqual(probe.report['auth_input_operations_delivered'],3)
                    self.assertFalse(receipt['server_token_revocation_verified'])
                    self.assertTrue(receipt['guest_marketplace_home_observed'])
                    self.assertTrue(receipt['guest_gate_observed'])
                    self.assertTrue(receipt['post_logout_account_tap_delivered'])
                    self.assertFalse(probe.native_auth_uncertain)
                    self.assertIsNone(probe.active_native_role)
                    self.assertNotIn('actions',probe.report)
                    self.assertNotIn('frames',probe.report)
                    self.assertNotIn('witness',json.dumps(receipt))

    def test_regular_same_four_footer_labels_are_insufficient_without_home_anchor(self):
        self.blocked([[row(name) for name in self.module.ROLE_NAV['regular']]])

    def test_broker_standalone_route_relaunches_once_before_normal_logout(self):
        probe=FakeProbe(self.module,'broker')
        probe.stage='standalone_my_listings'
        receipt=self.module.native_logout_role(probe)
        self.assertEqual(receipt['status'],'PASS_WITHIN_LOGOUT_UI_SCOPE')
        self.assertTrue(receipt['retained_broker_home_observed'])
        self.assertEqual(probe.events[:5],[('lifecycle','close'),('lifecycle','force-stop'),
            ('lifecycle','startup'),('read','broker_home'),('tap','حسابي')])
        self.assertEqual(self.taps(probe),['حسابي','تسجيل الخروج','حسابي'])
        self.assertEqual([x for x in probe.events if x[0]=='lifecycle'],
            [('lifecycle','close'),('lifecycle','force-stop'),('lifecycle','startup')])
        self.assertNotIn('actions',probe.report)

    def test_broker_relaunch_requires_visible_same_role_before_any_account_tap(self):
        for rows in ([row(label) for label in self.module.ROLE_NAV['regular']],
                     [row(label,visible=False) for label in self.module.ROLE_NAV['broker']],
                     [row(label,package='foreign') for label in self.module.ROLE_NAV['broker']],
                     [row(label) for label in self.module.ROLE_NAV['broker']]+[row('مرحبًا بعودتك')]):
            with self.subTest(rows=rows):
                probe=FakeProbe(self.module,'broker');probe.retained_rows=rows
                receipt=self.module.native_logout_role(probe)
                self.assertEqual(receipt['status'],'BLOCKED')
                self.assertEqual(receipt['reason'],'retained_broker_home_not_observed')
                self.assertEqual(self.taps(probe),[])
                self.assertTrue(probe.native_auth_uncertain)

    def test_uncertain_broker_startup_never_retries_or_claims_logout(self):
        probe=FakeProbe(self.module,'broker');probe.startup_error='SYNTHETIC_PRIVATE_ERROR'
        receipt=self.module.native_logout_role(probe)
        self.assertEqual(receipt['status'],'BLOCKED')
        self.assertEqual(receipt['reason'],'controller_operation_blocked')
        self.assertEqual(self.taps(probe),[])
        self.assertTrue(probe.native_auth_uncertain)
        self.assertNotIn('retained_broker_home_observed',receipt)

    def test_support_queue_pops_observed_named_back_once_before_normal_logout(self):
        probe=FakeProbe(self.module,'support');probe.stage='support_queue'
        receipt=self.module.native_logout_role(probe)
        self.assertEqual(receipt['status'],'PASS_WITHIN_LOGOUT_UI_SCOPE')
        self.assertTrue(receipt['support_shell_before_logout_observed'])
        self.assertEqual(self.taps(probe),['رجوع','حسابي','تسجيل الخروج','حسابي'])
        self.assertFalse(any(kind=='lifecycle' for kind,label in probe.events))

    def test_support_back_requires_actual_queue_and_visible_named_control(self):
        for rows in ([row('رجوع')], [row('تحقيق الإعلانات'),row('طلبات التحقيق')],
                     [row('تحقيق الإعلانات'),row('طلبات التحقيق'),row('رجوع',visible=False)],
                     [row('تحقيق الإعلانات'),row('طلبات التحقيق'),row('رجوع'),row('رمز التحقق')]):
            probe=FakeProbe(self.module,'support');probe.stage='support_queue';probe.support_queue_rows=rows
            receipt=self.module.native_logout_role(probe)
            self.assertEqual(receipt['status'],'BLOCKED')
            self.assertEqual(receipt['reason'],'support_queue_before_logout_required')
            self.assertEqual(self.taps(probe),[])

    def test_support_back_does_not_logout_if_expected_shell_was_not_restored(self):
        probe=FakeProbe(self.module,'support');probe.stage='support_queue'
        probe.support_shell_rows=[row(label) for label in self.module.ROLE_NAV['regular']]
        receipt=self.module.native_logout_role(probe)
        self.assertEqual(receipt['status'],'BLOCKED')
        self.assertEqual(receipt['reason'],'support_shell_before_logout_required')
        self.assertEqual(self.taps(probe),['رجوع'])
        self.assertTrue(probe.native_auth_uncertain)

    def test_hidden_home_anchor_cannot_satisfy_transition(self):
        frames=home(self.module)
        frames[-1]['visible']=False
        self.blocked([frames])

    def test_foreign_package_home_anchor_cannot_satisfy_transition(self):
        frames=home(self.module)
        frames[-1]['package']='foreign.synthetic.app'
        self.blocked([frames])

    def test_missing_or_hidden_footer_control_blocks_even_with_home_anchor(self):
        self.blocked([home(self.module,footer={'العقارات','الرسائل','حسابي'})])
        self.module.time=Clock()
        frames=home(self.module)
        next(r for r in frames if r['text']=='إعلاناتي')['visible']=False
        self.blocked([frames])

    def test_old_role_logout_or_auth_controls_block_home_match(self):
        for forbidden in ['عملي','لوحة الدعم','تسجيل الخروج','رمز التحقق']:
            with self.subTest(control=forbidden):
                self.module.time=Clock()
                self.blocked([home(self.module)+[row(forbidden)]])

    def test_delayed_home_poll_is_read_only_until_actual_anchor_observed(self):
        footer=[row(name) for name in self.module.GUEST_HOME_NAV]
        hidden=home(self.module); hidden[-1]['visible']=False
        probe=FakeProbe(self.module,'regular',[footer,hidden,home(self.module)])
        receipt=self.module.native_logout_role(probe)
        self.assertEqual(receipt['status'],'PASS_WITHIN_LOGOUT_UI_SCOPE')
        self.assertEqual(probe.reads,3)
        self.assertEqual(probe.events[:6],[('tap','حسابي'),('tap','تسجيل الخروج'),
            ('read','after_logout'),('read','after_logout'),('read','after_logout'),('tap','حسابي')])
        self.assertEqual(self.taps(probe).count('تسجيل الخروج'),1)

    def test_deadline_refusal_after_home_never_repeats_account_or_logout(self):
        probe=FakeProbe(self.module)
        probe.expire_after_home=True
        receipt=self.module.native_logout_role(probe)
        self.assertEqual(receipt['status'],'BLOCKED')
        self.assertEqual(receipt['reason'],'controller_operation_blocked')
        self.assertEqual(self.taps(probe),['حسابي','تسجيل الخروج','حسابي'])
        self.assertTrue(probe.native_auth_uncertain)
        self.assertIsNotNone(probe.active_native_role)

    def test_final_guest_gate_must_be_visible_app_and_have_no_logout_or_auth(self):
        for extra in [[row('تسجيل الخروج')],[row('مرحبًا بعودتك')],
                      [row('تسجيل الدخول أو إنشاء حساب',visible=False)],
                      [row('تسجيل الدخول أو إنشاء حساب',package='foreign.synthetic.app')]]:
            with self.subTest(surface=extra):
                self.module.time=Clock()
                probe=FakeProbe(self.module)
                if extra[0]['text']=='تسجيل الدخول أو إنشاء حساب':probe.guest_rows=extra
                else:probe.guest_rows+=extra
                receipt=self.module.native_logout_role(probe)
                self.assertEqual(receipt['status'],'BLOCKED')
                self.assertEqual(receipt['reason'],'native_guest_logout_state_not_observed')
                self.assertTrue(probe.native_auth_uncertain)
                self.assertEqual(self.taps(probe),['حسابي','تسجيل الخروج','حسابي'])

    def test_unknown_read_error_is_fixed_and_does_not_retry_or_export_text(self):
        probe=FakeProbe(self.module);probe.read_error='SYNTHETIC_PRIVATE_ERROR'
        receipt=self.module.native_logout_role(probe)
        self.assertEqual(receipt['reason'],'controller_operation_blocked')
        self.assertNotIn('SYNTHETIC_PRIVATE_ERROR',json.dumps(receipt))
        self.assertEqual(self.taps(probe),['حسابي','تسجيل الخروج'])

    def test_recording_and_unknown_actor_refuse_before_any_input(self):
        for attribute,value in [('recorder',object()),('active_native_role','unknown')]:
            probe=FakeProbe(self.module);setattr(probe,attribute,value)
            with self.assertRaises(self.module.RouteBlocked):self.module.native_logout_role(probe)
            self.assertEqual(probe.events,[])

    def test_reviewed_logout_capture_and_generated_digit_variants_match_pins(self):
        for name,pinned in PREVIOUS_UNCHANGED.items():
            self.assertEqual(hashlib.sha256((HERE/name).read_bytes()).hexdigest(),pinned,name)
        # The baseline digest is the prior frozen module AST with ONLY the
        # reviewed logout/safe-error functions removed. This works in packaged
        # CI too; no old adapter directory or original source tree is required.
        tree=ast.parse((HERE/'variants'/ROLE_PATH).read_text())
        ignored_functions={'native_logout_role','_safe_role_failure','_visible_app_names'}
        ignored_constants={'GUEST_HOME_ANCHORS','GUEST_HOME_NAV'}
        unchanged=[]
        for node in tree.body:
            if isinstance(node,(ast.FunctionDef,ast.ClassDef)) and node.name in ignored_functions:continue
            if isinstance(node,ast.Assign) and any(isinstance(t,ast.Name) and t.id in ignored_constants for t in node.targets):continue
            unchanged.append(node)
        actual=hashlib.sha256(ast.dump(ast.Module(body=unchanged,type_ignores=[]),include_attributes=False).encode()).hexdigest()
        self.assertEqual(actual,'da104e82dabc587d1a17fdf94337ba2ee0ad8f3d9e3011aebecff5d6591d5ce6')
        manifest=json.loads((HERE/'variants/VARIANT_MANIFEST.json').read_text())['manifest'][ROLE_PATH]
        self.assertEqual(manifest['original_sha256'],'789a790fa1bbced95653cf0ecf66190420b814caf15c73189f5b783c5efc183c')
        self.assertEqual(manifest['previous_utc_variant_sha256'],'cfec7b46f3d37b68c6432893435cd37c970b6713561c644ca6adbc562d635b6c')
        self.assertEqual(manifest['sha256'],hashlib.sha256((HERE/'variants'/ROLE_PATH).read_bytes()).hexdigest())


if __name__=='__main__':unittest.main()
