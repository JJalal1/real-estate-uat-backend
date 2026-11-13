import email.message
import sys
import unittest
from pathlib import Path
from unittest.mock import Mock

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from phase23_document_access import head_document, accepted


class DocumentHeaderProbeTest(unittest.TestCase):
    def test_only_fixed_origin_head_is_sent_and_body_is_never_read(self):
        headers = email.message.Message()
        headers['Content-Type'] = 'image/png'
        headers['Cache-Control'] = 'no-store, private'
        response = Mock(code=200, headers=headers)
        response.__enter__ = Mock(return_value=response)
        response.__exit__ = Mock(return_value=False)
        opener = Mock()
        opener.open.return_value = response
        row = head_document('selfie', 'synthetic-token', opener)
        request = opener.open.call_args.args[0]
        self.assertEqual(request.get_method(), 'HEAD')
        self.assertEqual(request.full_url, 'https://real-estate-uat-api-frankfurt.onrender.com/api/account-verification/users/25/documents/selfie')
        response.read.assert_not_called()
        self.assertTrue(accepted(row, 200))

    def test_arbitrary_target_is_refused_before_transport(self):
        opener = Mock()
        with self.assertRaises(ValueError):
            head_document('../users/26', opener=opener)
        opener.open.assert_not_called()

    def test_property_proof_uses_only_the_inventoried_fixed_document(self):
        headers = email.message.Message()
        headers['Content-Type'] = 'image/png'
        headers['Cache-Control'] = 'private, no-store'
        response = Mock(code=200, headers=headers)
        response.__enter__ = Mock(return_value=response)
        response.__exit__ = Mock(return_value=False)
        opener = Mock()
        opener.open.return_value = response
        self.assertTrue(accepted(head_document('ownership_proof', opener=opener), 200))
        self.assertEqual(opener.open.call_args.args[0].full_url,
                         'https://real-estate-uat-api-frankfurt.onrender.com/api/listing-documents/23')
        response.read.assert_not_called()

    def test_redirect_and_public_cache_never_count_as_private_success(self):
        base = {'http': 200, 'redirect_received': False,
                'content_type': 'image/png', 'cache_control': 'public, max-age=3600'}
        self.assertFalse(accepted(base, 200))
        self.assertFalse(accepted({**base, 'http': 302, 'redirect_received': True}, 302))
        self.assertFalse(accepted({**base, 'http': 200}, 403))


if __name__ == '__main__':
    unittest.main()
