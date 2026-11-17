import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import uat_signing_identity as subject


class PublicSigningIdentityTests(unittest.TestCase):
    def setUp(self):
        self.pending = subject.load_public_identity()

    def approved(self):
        return {**self.pending, 'approved_for_delivery': True, 'github_secret_storage_verified': True}

    def load_fixture(self, identity, **kwargs):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'public-identity.json'
            path.write_text(json.dumps(identity))
            return subject.load_public_identity(path, **kwargs)

    def test_public_policy_can_be_read_while_delivery_is_unapproved(self):
        identity = {**self.pending, 'approved_for_delivery': False, 'github_secret_storage_verified': False}
        self.assertFalse(subject.approval_ready(self.load_fixture(identity)))
        with self.assertRaises(subject.IdentityError):
            self.load_fixture(identity, require_approval=True)

    def test_both_explicit_flags_are_required(self):
        for field in ('approved_for_delivery', 'github_secret_storage_verified'):
            with self.subTest(field=field), self.assertRaises(subject.IdentityError):
                self.load_fixture({**self.approved(), field: False}, require_approval=True)
        self.assertTrue(subject.approval_ready(self.load_fixture(self.approved(), require_approval=True)))

    def test_string_approval_is_not_boolean_approval(self):
        for field in subject.BOOLEAN_FIELDS:
            with self.subTest(field=field), self.assertRaises(subject.IdentityError):
                self.load_fixture({**self.approved(), field: 'true'})

    def test_identity_namespace_or_transition_cannot_change_silently(self):
        for field, value in (('package', 'com.aqer.yemen.uat.another'),
                             ('application_name', 'Another app'),
                             ('first_durable_version', 1817),
                             ('transition_from_1815', 'same_signer_update')):
            with self.subTest(field=field), self.assertRaises(subject.IdentityError):
                self.load_fixture({**self.approved(), field: value})

    def test_certificate_pin_is_exact_and_transition_has_distinct_signer(self):
        for value in ('invalid', 'A' * 64, self.pending['previous_1815_certificate_sha256']):
            with self.subTest(value=value), self.assertRaises(subject.IdentityError):
                self.load_fixture({**self.approved(), 'certificate_sha256': value})

    def test_private_fields_or_disclosure_are_rejected(self):
        for identity in ({**self.approved(), 'private_key': 'synthetic-forbidden-field'},
                         {**self.approved(), 'private_key_disclosed_in_artifacts': True}):
            with self.assertRaises(subject.IdentityError):
                self.load_fixture(identity)

    def test_missing_any_signing_input_blocks_build_even_after_approval(self):
        for missing in subject.PRESENCE_NAMES:
            present = {name: name != missing for name in subject.PRESENCE_NAMES}
            result = subject.signing_readiness(self.approved(), present, True)
            self.assertFalse(result['compatible'])
            self.assertEqual(result['status'], 'blocked_missing_signing_configuration')

    def test_presence_and_pin_never_bypass_pending_approval(self):
        present = dict.fromkeys(subject.PRESENCE_NAMES, True)
        identity = {**self.pending, 'approved_for_delivery': False, 'github_secret_storage_verified': False}
        result = subject.signing_readiness(identity, present, True)
        self.assertFalse(result['compatible'])
        self.assertFalse(result['signing_material_verified'])

    def test_public_pin_mismatch_blocks_build_after_approval(self):
        result = subject.signing_readiness(self.approved(), dict.fromkeys(subject.PRESENCE_NAMES, True), False)
        self.assertFalse(result['compatible'])
        self.assertEqual(result['status'], 'blocked_public_policy_pin_mismatch')

    def test_only_boolean_presence_is_accepted(self):
        with self.assertRaises(subject.IdentityError):
            subject.signing_readiness(self.approved(), dict.fromkeys(subject.PRESENCE_NAMES, 'true'), True)

    def test_ready_means_presence_only_until_private_importer_runs(self):
        result = subject.signing_readiness(self.approved(), dict.fromkeys(subject.PRESENCE_NAMES, True), True)
        self.assertTrue(result['compatible'])
        self.assertFalse(result['signing_material_verified'])
        self.assertFalse(result['upgrade_from_1815_compatible'])

    def test_imported_signer_and_debug_flag_must_match_public_policy(self):
        env = {'AQER_SIGNING_ENVIRONMENT': 'uat', 'AQER_UAT_SIGNING_CONFIGURED': 'true',
               'AQER_ALLOW_DEBUG_RELEASE_SIGNING': 'false',
               'AQER_UAT_SIGNING_CERT_SHA256': self.pending['certificate_sha256']}
        subject.verify_imported_environment(self.approved(), env)
        for name, value in (('AQER_SIGNING_ENVIRONMENT', 'production'),
                            ('AQER_UAT_SIGNING_CONFIGURED', 'false'),
                            ('AQER_ALLOW_DEBUG_RELEASE_SIGNING', 'true'),
                            ('AQER_UAT_SIGNING_CERT_SHA256', self.pending['previous_1815_certificate_sha256'])):
            with self.subTest(name=name), self.assertRaises(subject.IdentityError):
                subject.verify_imported_environment(self.approved(), {**env, name: value})


if __name__ == '__main__':
    unittest.main()
