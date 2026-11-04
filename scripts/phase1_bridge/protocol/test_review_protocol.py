"""Offline protocol boundaries using generated test keys and invented records."""
from dataclasses import replace
from datetime import datetime, timedelta, timezone
import base64
import hashlib
import json
import os
from pathlib import Path
import stat
import tempfile
import unittest
from unittest.mock import Mock, patch

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.asymmetric.x25519 import X25519PrivateKey
from cryptography.hazmat.primitives.ciphers.aead import AESGCM

import review_protocol as p


class ProtocolBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.root_key = Ed25519PrivateKey.generate()
        self.job_key = p.JobEphemeralKey()
        self.now = datetime(2026, 11, 4, 1, 2, 3, tzinfo=timezone.utc)
        self.ctx = p.Context(p.REPOSITORY, '9001', 2, 'a' * 40, 'b' * 64, 1,
                             'C4', 'AI_REVIEW', 'c' * 64, 'd' * 64, '0' * 64)
        self.review = {'actual_frames_reviewed': True, 'frame_sha': 'e' * 64,
                       'review_completed_utc': '2026-11-04T01:02:02Z',
                       'facts': {'floor': 2, 'unit': '7'}, 'frames': ['C4-ai.png']}
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name) / 'ledger'
        self.ledger = p.ConsumeLedger(self.directory)
        self.addCleanup(self.ledger.close)
        self.dispatch = Mock(return_value=True)
        self.scene = Mock(return_value=True)

    def command(self, *, context=None, review=None, now=None, op='advance', ttl=90):
        return p.build_command(context or self.ctx, self.review if review is None else review,
                               self.root_key, self.job_key.public(), now or self.now,
                               op=op, ttl_seconds=ttl)

    def validate(self, raw, *, context=None, now=None, key=None, job=None, **kwargs):
        return p.validate_command(raw, context or self.ctx, key or self.root_key.public_key(),
                                  job or self.job_key, now or self.now, **kwargs)

    def receive(self, raw, *, context=None, now=None, **kwargs):
        return p.receive(raw, context=context or self.ctx,
                         root_public=self.root_key.public_key(), job_key=self.job_key,
                         ledger=self.ledger, now=now or self.now,
                         fresh_scene_check=self.scene, dispatch=self.dispatch, **kwargs)

    def resign(self, value):
        value = dict(value)
        value.pop('signature', None)
        value['signature'] = p._b64(self.root_key.sign(p.SIGN_DOMAIN + p.canonical(value)))
        return p.canonical(value)

    def encrypt_raw_review(self, plain):
        # Adversarial sender fixture: sign an intentionally malformed plaintext.
        value = json.loads(self.command())
        metadata = {name: value[name] for name in p.META_KEYS}
        aad = p.canonical(metadata)
        sender, salt, nonce = X25519PrivateKey.generate(), os.urandom(32), os.urandom(12)
        key = p._derive(sender, self.job_key.public(), salt, aad)
        value['encrypted_review_b64'] = p._b64(p.MAGIC + p.raw_public(sender.public_key())
            + salt + nonce + AESGCM(key).encrypt(nonce, plain, aad))
        return self.resign(value)

    def assert_no_dispatch(self):
        self.scene.assert_not_called()
        self.dispatch.assert_not_called()
        self.assertEqual(list(self.directory.iterdir()), [])

    def test_roundtrip_preserves_only_operator_supplied_review(self):
        result = self.validate(self.command())
        self.assertEqual(result.review, self.review)
        self.assertNotIn('accepted', result.review)
        self.assertNotIn('reviewed_monotonic', result.review)
        self.assertNotIn('actual_frames_reviewed', repr(result))
        self.assertEqual(list(self.directory.iterdir()), [])

    def test_ephemeral_encryption_is_random_and_job_scoped(self):
        first, second = self.command(), self.command()
        self.assertNotEqual(json.loads(first)['encrypted_review_b64'],
                            json.loads(second)['encrypted_review_b64'])
        self.assertEqual(self.validate(first).review, self.validate(second).review)
        with self.assertRaisesRegex(p.Refused, 'cipher_authentication'):
            self.validate(first, job=p.JobEphemeralKey())

    def test_root_key_is_pinned_and_signature_is_required(self):
        raw = self.command()
        with self.assertRaisesRegex(p.Refused, 'pinned_root_key'):
            self.validate(raw, key=Ed25519PrivateKey.generate().public_key())
        value = json.loads(raw)
        value['signature'] = p._b64(bytes(64))
        with self.assertRaisesRegex(p.Refused, 'root_signature'):
            self.receive(p.canonical(value))
        self.assert_no_dispatch()

    def test_tampered_ciphertext_is_rejected_before_decryption_or_reservation(self):
        value = json.loads(self.command())
        data = bytearray(base64.b64decode(value['encrypted_review_b64']))
        data[-1] ^= 1
        value['encrypted_review_b64'] = p._b64(bytes(data))
        with self.assertRaisesRegex(p.Refused, 'root_signature'):
            self.receive(p.canonical(value))
        self.assert_no_dispatch()

    def test_authentic_signature_does_not_bypass_cipher_authentication(self):
        value = json.loads(self.command())
        data = bytearray(base64.b64decode(value['encrypted_review_b64']))
        data[-1] ^= 1
        value['encrypted_review_b64'] = p._b64(bytes(data))
        with self.assertRaisesRegex(p.Refused, 'cipher_authentication'):
            self.receive(self.resign(value))
        self.assert_no_dispatch()

    def test_every_held_context_binding_is_checked(self):
        variants = {'repo': 'foreign/repository', 'run_id': '9002', 'run_attempt': 3,
                    'source_sha': 'f' * 40, 'toolbundle_sha': 'f' * 64, 'seq': 2,
                    'phase': 'C2', 'cursor': 'APPLY_REVIEW', 'checkpoint_challenge': 'f' * 64,
                    'cipher_sha': 'f' * 64, 'prev_result_sha': 'f' * 64}
        raw = self.command()
        for field, value in variants.items():
            with self.subTest(field=field), self.assertRaises(p.Refused):
                self.receive(raw, context=replace(self.ctx, **{field: value}))
        self.assert_no_dispatch()

    def test_aad_binds_metadata_even_if_sender_resigns_old_ciphertext(self):
        value = json.loads(self.command())
        value['checkpoint_challenge'] = 'f' * 64
        new_context = replace(self.ctx, checkpoint_challenge='f' * 64)
        with self.assertRaisesRegex(p.Refused, 'cipher_authentication'):
            self.receive(self.resign(value), context=new_context)
        self.assert_no_dispatch()

    def test_strict_json_rejects_duplicates_extra_keys_and_trailing_input(self):
        raw = self.command()
        for malformed in [raw[:-1] + b',"seq":1}', raw + b' {}',
                          p.canonical(dict(json.loads(raw), unexpected=True)),
                          raw.replace(b'"seq":1', b'"seq":NaN'), b'[]', b'\xff']:
            with self.subTest(kind=malformed[:15]), self.assertRaises(p.Refused):
                self.receive(malformed)
        self.assert_no_dispatch()

    def test_nested_review_duplicates_are_rejected_after_authenticated_decrypt(self):
        raw = self.encrypt_raw_review(b'{"frames":{"sha":"a","sha":"b"}}')
        with self.assertRaisesRegex(p.Refused, 'duplicate_json_key'):
            self.receive(raw)
        self.assert_no_dispatch()

    def test_size_and_numeric_type_bounds_reject_bools_floats_and_unknown_phase(self):
        for name, value in [('seq', True), ('run_attempt', True), ('version', True),
                            ('seq', 1.0), ('phase', []), ('phase', 'UNREVIEWED'),
                            ('run_id', 9001), ('root_key_id', 'uppercase-invalid')]:
            envelope = json.loads(self.command()); envelope[name] = value
            with self.subTest(field=name), self.assertRaises(p.Refused):
                self.receive(self.resign(envelope))
        with self.assertRaisesRegex(p.Refused, 'json_size'):
            self.receive(b' ' * (p.MAX_ENVELOPE_BYTES + 1))
        self.assert_no_dispatch()

    def test_base64_canonical_form_and_signature_size_are_enforced(self):
        for signature in ['', '%%%=', p._b64(b'x'), p._b64(bytes(64)) + '=']:
            value = json.loads(self.command()); value['signature'] = signature
            with self.subTest(size=len(signature)), self.assertRaises(p.Refused):
                self.receive(p.canonical(value))
        self.assert_no_dispatch()

    def test_ttl_is_positive_bounded_and_not_a_boolean(self):
        for ttl in [0, 121, True, 1.0]:
            with self.subTest(ttl=ttl), self.assertRaisesRegex(p.Refused, 'ttl_invalid'):
                self.command(ttl=ttl)
        value = json.loads(self.command()); value['expires_utc'] = '2026-11-04T01:04:04Z'
        with self.assertRaisesRegex(p.Refused, 'ttl_invalid'):
            self.receive(self.resign(value))

    def test_expiration_and_clock_skew_boundaries_are_exact(self):
        raw = self.command()
        self.validate(raw, now=self.now + timedelta(seconds=90))
        self.validate(raw, now=self.now - timedelta(seconds=5))
        for now, code in [(self.now + timedelta(seconds=90, microseconds=1), 'expired'),
                          (self.now - timedelta(seconds=5, microseconds=1), 'future')]:
            with self.subTest(code=code), self.assertRaisesRegex(p.Refused, code):
                self.receive(raw, now=now)
        self.assert_no_dispatch()

    def test_non_utc_clock_invalid_calendar_and_noncanonical_timestamps_fail_closed(self):
        with self.assertRaisesRegex(p.Refused, 'utc_clock'):
            self.validate(self.command(), now=datetime(2026, 11, 4))
        for stamp in ['2026-11-04T01:02:03+00:00', '2026-02-31T01:02:03Z',
                      '2026-11-04T01:02:03.000Z']:
            value = json.loads(self.command()); value['issued_utc'] = stamp
            with self.subTest(stamp=stamp), self.assertRaises(p.Refused):
                self.receive(self.resign(value))
        self.assert_no_dispatch()

    def test_plaintext_review_has_authentication_and_private_value_bounds(self):
        for review in [{'otp': 'invented'}, {'nested': {'access_token': 'invented'}},
                       {'description': '+999999999999'}, {'accepted': 0.5},
                       {'description': 'x' * 4097}, {'reviewed_monotonic': 123.5}]:
            with self.subTest(keys=list(review)), self.assertRaises(p.Refused):
                self.command(review=review)
        raw = self.command(review={'note': 'PRIVATE_ALIAS_SENTINEL'})
        with self.assertRaisesRegex(p.Refused, 'private_review_value'):
            self.receive(raw, forbidden_values=['PRIVATE_ALIAS_SENTINEL'])
        self.assert_no_dispatch()

    def test_signed_authenticated_payload_still_requires_review_bounds(self):
        for plain in [b'{"password":"PRIVATE_SENTINEL"}', b'{"accept":NaN}',
                      b'{"value":1e309}', b'[]', b'{"value":0.5}']:
            with self.subTest(prefix=plain[:12]), self.assertRaises(p.Refused) as error:
                self.receive(self.encrypt_raw_review(plain))
            self.assertNotIn('PRIVATE_SENTINEL', str(error.exception))
        self.assert_no_dispatch()

    def test_zero_shared_key_and_closed_job_key_are_refused(self):
        with self.assertRaisesRegex(p.Refused, 'key_exchange'):
            p.build_command(self.ctx, self.review, self.root_key, bytes(32), self.now)
        raw = self.command(); self.job_key.close()
        with self.assertRaisesRegex(p.Refused, 'job_key_closed'):
            self.receive(raw)
        self.assert_no_dispatch()

    def test_reservation_exists_before_scene_check_and_dispatch_and_contains_no_review(self):
        seen = []
        def scene(review):
            record = self.directory / '000001.command.json'
            self.assertTrue(record.is_file())
            self.assertEqual(stat.S_IMODE(record.stat().st_mode), 0o600)
            self.assertEqual(record.stat().st_nlink, 1)
            self.assertNotIn('actual_frames_reviewed', record.read_text())
            seen.append('reserved-before-scene')
            return True
        def dispatch(op, review):
            self.assertEqual(seen, ['reserved-before-scene'])
            self.assertEqual(op, 'advance'); self.assertEqual(review, self.review)
            seen.append('one-dispatch')
            return True
        self.scene.side_effect = scene; self.dispatch.side_effect = dispatch
        result = self.receive(self.command())
        self.assertEqual(result.status, 'executed')
        self.assertEqual(result.outcome, 'completed')
        self.assertEqual(seen, ['reserved-before-scene', 'one-dispatch'])

    def test_scene_checker_cannot_manufacture_root_flags_for_dispatch(self):
        def mutate_scene(review):
            review['manufactured_acceptance'] = True
            review['facts']['unit'] = '999'
            return True
        self.scene.side_effect = mutate_scene
        self.receive(self.command())
        delivered = self.dispatch.call_args.args[1]
        self.assertEqual(delivered, self.review)
        self.assertNotIn('manufactured_acceptance', delivered)

    def test_duplicate_exact_command_never_dispatches_twice_even_with_new_ledger_object(self):
        raw = self.command(); self.receive(raw)
        self.ledger.close(); self.ledger = p.ConsumeLedger(self.directory)
        self.addCleanup(self.ledger.close)
        result = self.receive(raw)
        self.assertEqual(result.status, 'already_consumed')
        self.assertEqual(result.outcome, 'completed')
        self.scene.assert_called_once(); self.dispatch.assert_called_once()

    def test_same_sequence_with_fresh_encryption_or_modified_payload_is_not_a_retry(self):
        self.receive(self.command())
        for raw in [self.command(), self.command(review={'actual_frames_reviewed': False})]:
            with self.assertRaisesRegex(p.Refused, 'consumed_sequence_payload_mismatch'):
                self.receive(raw)
        self.dispatch.assert_called_once()

    def test_uncertain_dispatch_is_consumed_and_exception_content_is_suppressed(self):
        raw = self.command()
        self.dispatch.side_effect = RuntimeError('PRIVATE_CALLBACK_SENTINEL')
        with self.assertRaisesRegex(p.Refused, '^dispatch_failed_uncertain$') as error:
            self.receive(raw)
        self.assertNotIn('PRIVATE_CALLBACK_SENTINEL', str(error.exception))
        result = self.receive(raw)
        self.assertEqual(result.outcome, 'failed_uncertain')
        self.dispatch.assert_called_once()
        self.assertNotIn('PRIVATE_CALLBACK_SENTINEL', ''.join(f.read_text() for f in self.directory.iterdir()))

    def test_fresh_scene_mismatch_consumes_without_dispatch_and_blocks_later_advance(self):
        raw = self.command(); self.scene.return_value = False
        with self.assertRaisesRegex(p.Refused, 'fresh_scene_mismatch'):
            self.receive(raw)
        self.assertEqual(self.receive(raw).outcome, 'scene_rejected')
        self.dispatch.assert_not_called()
        next_context = replace(self.ctx, seq=2, cursor='AFTER_AI')
        with self.assertRaisesRegex(p.Refused, 'uncertain_previous_advance_refused'):
            self.receive(self.command(context=next_context), context=next_context)
        self.dispatch.assert_not_called()

    def test_false_or_truthy_non_boolean_dispatch_result_is_uncertain(self):
        for result in [False, None, 1, 'PASS', {'status': 'PASS'}]:
            with self.subTest(result_type=type(result).__name__):
                temp = tempfile.TemporaryDirectory(); self.addCleanup(temp.cleanup)
                other = p.ConsumeLedger(Path(temp.name) / 'ledger'); self.addCleanup(other.close)
                with self.assertRaisesRegex(p.Refused, 'dispatch_not_confirmed'):
                    p.receive(self.command(), context=self.ctx,
                              root_public=self.root_key.public_key(), job_key=self.job_key,
                              ledger=other, now=self.now, fresh_scene_check=lambda _: True,
                              dispatch=lambda *_: result)

    def test_reject_or_finish_can_close_after_uncertainty_without_requiring_a_live_scene(self):
        raw = self.command(); self.dispatch.return_value = False
        with self.assertRaises(p.Refused): self.receive(raw)
        next_context = replace(self.ctx, seq=2, cursor='CLOSE')
        self.dispatch.return_value = True; self.scene.reset_mock()
        result = self.receive(self.command(context=next_context, op='finish', review={}), context=next_context)
        self.assertEqual(result.outcome, 'completed')
        self.scene.assert_not_called()
        self.assertEqual(self.dispatch.call_args.args, ('finish', {}))

    def test_missing_outcome_latches_sequence_and_only_close_can_follow(self):
        raw = self.command(); validated = self.validate(raw)
        self.ledger.reserve(validated)  # Simulated process loss after durable reserve.
        result = self.receive(raw)
        self.assertEqual(result.status, 'already_consumed')
        self.assertEqual(result.outcome, 'reserved_unobserved')
        self.scene.assert_not_called(); self.dispatch.assert_not_called()
        next_context = replace(self.ctx, seq=2)
        with self.assertRaisesRegex(p.Refused, 'uncertain_previous_advance_refused'):
            self.receive(self.command(context=next_context), context=next_context)

    def test_sequence_gap_and_ledger_unknown_entries_block_before_callbacks(self):
        context = replace(self.ctx, seq=2)
        with self.assertRaisesRegex(p.Refused, 'unexpected_next_sequence'):
            self.receive(self.command(context=context), context=context)
        (self.directory / 'untrusted.txt').write_text('not a command')
        with self.assertRaisesRegex(p.Refused, 'ledger_unknown_entry'):
            self.receive(self.command())
        self.scene.assert_not_called(); self.dispatch.assert_not_called()

    def test_orphan_outcome_is_not_silently_adopted(self):
        target = self.directory / '000001.outcome.json'
        target.write_text('{}'); target.chmod(0o600)
        with self.assertRaisesRegex(p.Refused, 'orphan_ledger_outcome'):
            self.receive(self.command())
        self.scene.assert_not_called(); self.dispatch.assert_not_called()

    def test_final_or_ancestor_symlink_and_broad_directory_modes_are_refused(self):
        root = Path(self.temp.name)
        (root / 'alias').symlink_to(self.directory, target_is_directory=True)
        for path in [root / 'alias', root / 'alias' / 'child']:
            with self.subTest(path=path.name), self.assertRaisesRegex(p.Refused, 'directory_required'):
                p.ConsumeLedger(path)
        broad = root / 'broad'; broad.mkdir(mode=0o755)
        with self.assertRaisesRegex(p.Refused, 'private_owned_ledger'):
            p.ConsumeLedger(broad)

    def test_symlink_hardlink_broad_or_partial_reservation_is_never_followed(self):
        raw = self.command()
        target = self.directory / '000001.command.json'
        outside = Path(self.temp.name) / 'outside'
        outside.write_text('{}'); outside.chmod(0o600)
        for kind in ['symlink', 'hardlink', 'broad', 'partial']:
            with self.subTest(kind=kind):
                if kind == 'symlink': target.symlink_to(outside)
                elif kind == 'hardlink': os.link(outside, target)
                else:
                    target.write_text('{}' if kind == 'broad' else '')
                    target.chmod(0o644 if kind == 'broad' else 0o600)
                with self.assertRaises(p.Refused): self.receive(raw)
                self.scene.assert_not_called(); self.dispatch.assert_not_called()
                target.unlink()
        self.assertEqual(outside.read_text(), '{}')

    def test_failed_fsync_prevents_any_scene_check_or_dispatch(self):
        with patch.object(p.os, 'fsync', side_effect=OSError('PRIVATE_FS_SENTINEL')):
            with self.assertRaisesRegex(p.Refused, '^ledger_write_failed$') as error:
                self.receive(self.command())
        self.assertNotIn('PRIVATE_FS_SENTINEL', str(error.exception))
        self.scene.assert_not_called(); self.dispatch.assert_not_called()
        self.assertTrue((self.directory / '000001.command.json').exists())

    def test_outcome_write_failure_never_allows_second_dispatch(self):
        raw = self.command()
        with patch.object(self.ledger, 'finish', side_effect=p.Refused('synthetic_outcome_write_failed')):
            with self.assertRaisesRegex(p.Refused, 'outcome_write_failed'):
                self.receive(raw)
        self.assertEqual(self.receive(raw).outcome, 'reserved_unobserved')
        self.dispatch.assert_called_once()

    def test_closed_ledger_cannot_fall_back_to_current_directory(self):
        self.ledger.close()
        with self.assertRaisesRegex(p.Refused, 'ledger_closed'):
            self.receive(self.command())
        self.scene.assert_not_called(); self.dispatch.assert_not_called()

    def test_ledger_cannot_be_reused_for_a_different_run_attempt_or_source(self):
        self.receive(self.command())
        for replacement in [{'run_id': '9002'}, {'run_attempt': 3}, {'source_sha': 'f' * 40},
                            {'toolbundle_sha': 'f' * 64}]:
            context = replace(self.ctx, seq=2, **replacement)
            with self.subTest(field=next(iter(replacement))), self.assertRaisesRegex(p.Refused, 'ledger_session_mismatch'):
                self.receive(self.command(context=context), context=context)
        self.dispatch.assert_called_once()

    def test_finish_or_reject_is_terminal_even_when_the_callback_reports_success(self):
        self.receive(self.command(op='finish', review={}))
        context = replace(self.ctx, seq=2)
        for op in ['advance', 'finish', 'reject']:
            with self.subTest(op=op), self.assertRaisesRegex(p.Refused, 'ledger_session_closed'):
                self.receive(self.command(context=context, op=op), context=context)
        self.dispatch.assert_called_once()

    def test_failed_advance_then_successful_finish_cannot_clear_latch_after_reopen(self):
        self.dispatch.return_value = False
        with self.assertRaisesRegex(p.Refused, 'dispatch_not_confirmed'):
            self.receive(self.command())
        closing = replace(self.ctx, seq=2, cursor='CLOSE')
        self.dispatch.return_value = True
        self.receive(self.command(context=closing, op='finish', review={}), context=closing)
        self.ledger.close(); self.ledger = p.ConsumeLedger(self.directory)
        self.addCleanup(self.ledger.close)
        forbidden = replace(self.ctx, seq=3)
        with self.assertRaisesRegex(p.Refused, 'ledger_session_closed'):
            self.receive(self.command(context=forbidden), context=forbidden)
        self.assertEqual(self.dispatch.call_count, 2)

    def test_slow_scene_check_cannot_dispatch_after_signed_expiry(self):
        raw = self.command(ttl=1)
        with patch.object(p.time, 'monotonic', side_effect=[100.0, 100.1, 101.1]):
            with self.assertRaisesRegex(p.Refused, '^command_expired_before_dispatch$'):
                self.receive(raw)
        self.scene.assert_called_once(); self.dispatch.assert_not_called()
        self.assertEqual(self.receive(raw).outcome, 'failed_uncertain')

    def test_distinct_sequences_cannot_overlap_even_with_a_second_ledger_object(self):
        another = p.ConsumeLedger(self.directory); self.addCleanup(another.close)
        closing = replace(self.ctx, seq=2, cursor='CLOSE')
        second = self.command(context=closing, op='finish', review={})
        def during_dispatch(op, review):
            for selected in [self.ledger, another]:
                with self.assertRaisesRegex(p.Refused, '^owner_transaction_busy$'):
                    p.receive(second, context=closing, root_public=self.root_key.public_key(),
                              job_key=self.job_key, ledger=selected, now=self.now,
                              fresh_scene_check=lambda _: True, dispatch=lambda *_: True)
            self.assertFalse((self.directory / '000002.command.json').exists())
            return True
        self.dispatch.side_effect = during_dispatch
        self.receive(self.command())
        self.dispatch.assert_called_once()

    def test_owner_interruption_still_consumes_the_sequence(self):
        raw = self.command(); self.dispatch.side_effect = KeyboardInterrupt()
        with self.assertRaises(KeyboardInterrupt):
            self.receive(raw)
        self.assertEqual(self.receive(raw).outcome, 'failed_uncertain')
        self.dispatch.assert_called_once()


if __name__ == '__main__':
    unittest.main()
