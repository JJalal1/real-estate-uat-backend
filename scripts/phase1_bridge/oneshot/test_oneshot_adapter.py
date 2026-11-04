"""Offline concurrency and privacy boundaries; no devices or network involved."""
import base64
import json
from pathlib import Path
import subprocess
import sys
import threading
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
from oneshot_adapter import AdmissionError, OneShotAdmission, OneShotInstrumentAdapter


NODE = {'node_path': '0.1', 'node_witness': 'a' * 64}


def completion(op, **extras):
    row = {'passed': 'true', 'op': op}
    if op == 'account-snapshot':
        row['tree_b64'] = base64.b64encode(b'[]').decode()
    else:
        row['account_action_delivered'] = 'true'
        if op == 'account-set':
            row['set_text_delivered'] = 'true'
    return row


class OneShotBoundaryTests(unittest.TestCase):
    def test_exact_short_scroll_extension_is_reserved_once_and_other_extensions_remain_closed(self):
        calls=[]
        def driver(op,**extras):
            calls.append((op,extras));return completion(op,**extras)
        adapter=OneShotInstrumentAdapter(driver);epoch=adapter.start()
        extras=dict(NODE,direction='forward',scroll_step='short')
        adapter.instrument('account-scroll',expected_epoch=epoch,**extras)
        self.assertEqual(calls,[('account-scroll',extras)])
        bad=[('account-scroll',dict(NODE,direction='forward',scroll_step=value))
             for value in ['normal','arbitrary',True,1,None]]
        bad += [('account-click',dict(NODE,scroll_step='short')),
                ('account-scroll',dict(extras,input_mode='physical_scroll')),
                ('account-scroll',dict(extras,deadline_utc_ms='1793754123000'))]
        for op,values in bad:
            with self.assertRaisesRegex(AdmissionError,'^unsupported_instrumentation_request$'):
                adapter.instrument(op,expected_epoch=epoch,**values)
        self.assertEqual(len(calls),1)
        self.assertEqual(adapter.metrics['reserved_calls'],1)
        self.assertEqual(adapter.metrics['checked_calls_completed'],1)
        self.assertEqual(adapter.metrics['state'],'open')

    def test_closed_gate_performs_no_driver_call(self):
        calls = []
        adapter = OneShotInstrumentAdapter(lambda *a, **k: calls.append(True))
        with self.assertRaisesRegex(AdmissionError, '^admission_closed$'):
            adapter.instrument('account-snapshot', expected_epoch=0)
        self.assertEqual(calls, [])
        self.assertEqual(adapter.metrics['reserved_calls'], 0)
        self.assertIsNone(adapter.metrics['last_reserved_call_completion_known'])

    def test_start_is_an_explicit_epoch_not_idempotent_connection_setup(self):
        adapter = OneShotInstrumentAdapter(completion)
        self.assertEqual(adapter.start(), 1)
        with self.assertRaisesRegex(AdmissionError, '^admission_already_open$'):
            adapter.start()
        self.assertEqual(adapter.stop()['state'], 'closed')
        self.assertEqual(adapter.start(), 2)
        self.assertFalse(adapter.metrics['persistent_connection_claimed'])

    def test_epoch_is_required_and_stale_epoch_never_dispatches(self):
        calls = []
        def driver(op, **extras):
            calls.append(op)
            return completion(op, **extras)
        adapter = OneShotInstrumentAdapter(driver)
        epoch = adapter.start()
        with self.assertRaises(TypeError):
            adapter.instrument('account-snapshot')
        adapter.instrument('account-snapshot', expected_epoch=epoch)
        adapter.stop()
        later = adapter.start()
        for stale in [epoch, 0, True, str(later)]:
            with self.subTest(stale_type=type(stale).__name__):
                with self.assertRaisesRegex(AdmissionError, '^admission_epoch_mismatch$'):
                    adapter.instrument('account-snapshot', expected_epoch=stale)
        self.assertEqual(calls, ['account-snapshot'])
        adapter.instrument('account-snapshot', expected_epoch=later)
        self.assertEqual(calls, ['account-snapshot', 'account-snapshot'])

    def test_fixed_operation_and_argument_schema_rejects_before_reservation(self):
        calls = []
        adapter = OneShotInstrumentAdapter(lambda *a, **k: calls.append(True))
        epoch = adapter.start()
        requests = [
            ('arbitrary-private-operation', {}),
            ('account-pointer-click', NODE),
            ('account-card-pointer-click', NODE),
            ('account-snapshot', {'value_b64': 'private-payload'}),
            ('account-click', {}),
            ('account-click', dict(NODE, node_path='../../foreign')),
            ('account-click', dict(NODE, node_witness='PRIVATE-WITNESS')),
            ('account-set', dict(NODE, value_b64='*private*')),
            ('account-set', dict(NODE, value_b64='A' * 12001)),
            ('account-set', dict(NODE, value_b64='', input_mode='explicit_pointer')),
            ('account-scroll', dict(NODE, direction='arbitrary-private-direction')),
        ]
        for op, extras in requests:
            with self.subTest(request_index=requests.index((op, extras))):
                with self.assertRaisesRegex(AdmissionError, '^unsupported_instrumentation_request$'):
                    adapter.instrument(op, expected_epoch=epoch, **extras)
        self.assertEqual(calls, [])
        self.assertEqual(adapter.metrics['reserved_calls'], 0)
        self.assertEqual(adapter.metrics['state'], 'open')

    def test_supported_calls_have_reservation_visible_before_driver_execution(self):
        observations = []
        adapter = None
        def driver(op, **extras):
            observations.append(adapter.metrics)
            return completion(op, **extras)
        adapter = OneShotInstrumentAdapter(driver)
        epoch = adapter.start()
        calls = [('account-snapshot', {}), ('account-click', NODE),
                 ('account-set', dict(NODE, value_b64=base64.b64encode(b'synthetic input').decode())),
                 ('account-scroll', dict(NODE, direction='backward'))]
        for op, extras in calls:
            self.assertEqual(adapter.instrument(op, expected_epoch=epoch, **extras)['op'], op)
        self.assertEqual([m['reserved_calls'] for m in observations], [1, 2, 3, 4])
        self.assertTrue(all(m['inflight'] == 1 and
                            m['last_reserved_call_completion_known'] is False for m in observations))
        self.assertEqual(adapter.metrics['checked_calls_completed'], 4)
        self.assertEqual(adapter.stop()['inflight'], 0)

    def test_real_thread_barrier_refuses_second_dispatch_and_stop_while_inflight(self):
        entered, release = threading.Event(), threading.Event()
        calls, results, errors = [], [], []
        def driver(op, **extras):
            calls.append(op)
            entered.set()
            if not release.wait(3):
                raise RuntimeError('synthetic barrier timeout')
            return completion(op, **extras)
        adapter = OneShotInstrumentAdapter(driver)
        epoch = adapter.start()
        def worker():
            try:
                results.append(adapter.instrument('account-snapshot', expected_epoch=epoch))
            except BaseException as error:
                errors.append(type(error).__name__)
        thread = threading.Thread(target=worker)
        thread.start()
        try:
            self.assertTrue(entered.wait(2))
            self.assertEqual(adapter.metrics['reserved_calls'], 1)
            for call in [lambda: adapter.instrument('account-click', expected_epoch=epoch, **NODE),
                         adapter.stop, adapter.start]:
                with self.assertRaisesRegex(AdmissionError, '^instrumentation_inflight$'):
                    call()
            self.assertEqual(calls, ['account-snapshot'])
            self.assertEqual(adapter.metrics['inflight'], 1)
        finally:
            release.set()
            thread.join(3)
        self.assertFalse(thread.is_alive())
        self.assertEqual(errors, [])
        self.assertEqual(len(results), 1)
        self.assertEqual(adapter.metrics['checked_calls_completed'], 1)
        self.assertEqual(adapter.stop()['state'], 'closed')

    def test_driver_errors_latch_forever_without_exception_or_argument_retention(self):
        private = 'SYNTHETIC_PRIVATE_SENTINEL'
        for error in [subprocess.TimeoutExpired(['private-command', private], 45),
                      RuntimeError(private), OSError(private), KeyboardInterrupt(private),
                      SystemExit(private)]:
            calls = []
            def failed(op, **extras):
                calls.append(True)
                raise error
            adapter = OneShotInstrumentAdapter(failed)
            epoch = adapter.start()
            with self.subTest(error_type=type(error).__name__):
                try:
                    adapter.instrument('account-set', expected_epoch=epoch, **NODE,
                                       value_b64=base64.b64encode(private.encode()).decode())
                except AdmissionError as caught:
                    self.assertEqual(str(caught), 'instrumentation_completion_uncertain')
                    self.assertIsNone(caught.__context__)
                    self.assertIsNone(caught.__cause__)
                else:
                    self.fail('unknown completion accepted')
                for call in [adapter.start, adapter.stop,
                             lambda: adapter.instrument('account-snapshot', expected_epoch=epoch)]:
                    with self.assertRaisesRegex(AdmissionError, '^admission_uncertain$'):
                        call()
                self.assertEqual(calls, [True])
                metrics = adapter.metrics
                self.assertEqual(metrics['state'], 'uncertain')
                self.assertEqual(metrics['inflight'], 0)
                self.assertFalse(metrics['last_reserved_call_completion_known'])
                self.assertEqual(metrics['reserved_calls'], 1)
                self.assertEqual(metrics['checked_calls_completed'], 0)
                self.assertEqual(metrics['uncertain_calls'], 1)
                safe = json.dumps(metrics) + repr(adapter) + repr(adapter._admission)
                for omitted in [private, base64.b64encode(private.encode()).decode(),
                                'private-command', 'node_witness', NODE['node_witness']]:
                    self.assertNotIn(omitted, safe)

    def test_threaded_unknown_completion_blocks_both_concurrent_and_later_calls(self):
        entered, release = threading.Event(), threading.Event()
        calls, failures = [], []
        def driver(op, **extras):
            calls.append(op)
            entered.set()
            if not release.wait(3):
                raise RuntimeError('synthetic barrier timeout')
            raise RuntimeError('SYNTHETIC_PRIVATE_UNKNOWN_COMPLETION')
        adapter = OneShotInstrumentAdapter(driver)
        epoch = adapter.start()
        def worker():
            try:
                adapter.instrument('account-snapshot', expected_epoch=epoch)
            except AdmissionError as error:
                failures.append(str(error))
        thread = threading.Thread(target=worker)
        thread.start()
        try:
            self.assertTrue(entered.wait(2))
            with self.assertRaisesRegex(AdmissionError, '^instrumentation_inflight$'):
                adapter.instrument('account-click', expected_epoch=epoch, **NODE)
        finally:
            release.set()
            thread.join(3)
        self.assertFalse(thread.is_alive())
        self.assertEqual(failures, ['instrumentation_completion_uncertain'])
        for call in [adapter.start, adapter.stop,
                     lambda: adapter.instrument('account-click', expected_epoch=epoch, **NODE)]:
            with self.assertRaisesRegex(AdmissionError, '^admission_uncertain$'):
                call()
        self.assertEqual(calls, ['account-snapshot'])
        self.assertEqual(adapter.metrics['reserved_calls'], 1)

    def test_malformed_or_failed_driver_receipts_are_also_uncertain_no_replay(self):
        returns = [None, [], {}, {'passed': 'false', 'op': 'account-snapshot'},
                   {'passed': 'true', 'op': 'foreign-op', 'tree_b64': 'W10='},
                   {'passed': 'true', 'op': 'account-snapshot'},
                   {'passed': 'true', 'op': 'account-snapshot', 'tree_b64': ''},
                   {'passed': 'true', 'op': 'account-snapshot', 'tree_b64': '*not-base64*'},
                   {'passed': 'true', 'op': 'account-snapshot', 'tree_b64': 'not ascii \u0627'},
                   {'passed': True, 'op': 'account-snapshot', 'tree_b64': 'W10='}]
        for result in returns:
            calls = []
            def driver(op, **extras):
                calls.append(op)
                return result
            adapter = OneShotInstrumentAdapter(driver)
            epoch = adapter.start()
            with self.subTest(result_index=returns.index(result)):
                with self.assertRaisesRegex(AdmissionError, '^instrumentation_completion_uncertain$'):
                    adapter.instrument('account-snapshot', expected_epoch=epoch)
                with self.assertRaisesRegex(AdmissionError, '^admission_uncertain$'):
                    adapter.instrument('account-snapshot', expected_epoch=epoch)
                self.assertEqual(calls, ['account-snapshot'])

    def test_action_delivery_missing_or_failed_is_not_a_known_success(self):
        for op, extras, result in [
            ('account-click', NODE, {'passed': 'true', 'op': 'account-click'}),
            ('account-scroll', dict(NODE, direction='forward'),
             {'passed': 'true', 'op': 'account-scroll', 'account_action_delivered': 'false'}),
            ('account-set', dict(NODE, value_b64=''),
             {'passed': 'true', 'op': 'account-set', 'account_action_delivered': 'true'}),
        ]:
            adapter = OneShotInstrumentAdapter(lambda *a, **k: result)
            epoch = adapter.start()
            with self.subTest(op=op):
                with self.assertRaisesRegex(AdmissionError, '^instrumentation_completion_uncertain$'):
                    adapter.instrument(op, expected_epoch=epoch, **extras)
                self.assertEqual(adapter.metrics['state'], 'uncertain')

    def test_gate_shared_by_wrappers_preserves_same_owner_uncertainty(self):
        gate = OneShotAdmission()
        first = OneShotInstrumentAdapter(lambda *a, **k: None, admission=gate)
        second_calls = []
        second = OneShotInstrumentAdapter(lambda *a, **k: second_calls.append(True), admission=gate)
        epoch = first.start()
        with self.assertRaises(AdmissionError):
            first.instrument('account-snapshot', expected_epoch=epoch)
        with self.assertRaisesRegex(AdmissionError, '^admission_uncertain$'):
            second.start()
        with self.assertRaisesRegex(AdmissionError, '^admission_uncertain$'):
            second.instrument('account-snapshot', expected_epoch=epoch)
        self.assertEqual(second_calls, [])

    def test_safe_metrics_are_detached_and_never_contain_successful_tree_or_input(self):
        private = 'SYNTHETIC_PRIVATE_SENTINEL'
        payload = base64.b64encode(private.encode()).decode()
        def driver(op, **extras):
            result = completion(op, **extras)
            result['tree_b64'] = payload
            result['unused_private_value'] = private
            return result
        adapter = OneShotInstrumentAdapter(driver)
        epoch = adapter.start()
        returned = adapter.instrument('account-snapshot', expected_epoch=epoch)
        self.assertEqual(returned['unused_private_value'], private)
        projection = adapter.metrics
        projection['state'] = private
        projection['reserved_calls'] = -99
        self.assertEqual(adapter.metrics['state'], 'open')
        self.assertEqual(adapter.metrics['reserved_calls'], 1)
        safe = json.dumps(adapter.metrics) + repr(adapter)
        self.assertNotIn(private, safe)
        self.assertNotIn(payload, safe)
        self.assertNotIn('unused_private_value', safe)


if __name__ == '__main__':
    unittest.main()
