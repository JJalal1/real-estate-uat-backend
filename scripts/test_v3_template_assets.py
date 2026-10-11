import hashlib
import tempfile
import unittest
from pathlib import Path

from verify_template_assets import REFERENCE, verify


class TemplateAssetTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.path = "mobile_app/assets/ebroker/svg/add_shape.svg"
        self.file = self.root / self.path
        self.file.parent.mkdir(parents=True)
        self.file.write_bytes(b"original-svg")
        self.manifest = {"template_reference_commit": REFERENCE, "assets": [
            {"target": self.path, "bytes": 12, "sha256": hashlib.sha256(b"original-svg").hexdigest()},
        ]}

    def test_identical_source_passes(self):
        self.assertEqual(verify(self.root, self.manifest), 1)

    def test_recreated_similar_asset_fails(self):
        self.file.write_bytes(b"redrawn-icon")
        with self.assertRaisesRegex(ValueError, "checksum"):
            verify(self.root, self.manifest)

    def test_unrecorded_asset_fails(self):
        (self.file.parent / "other.svg").write_bytes(b"new")
        with self.assertRaisesRegex(ValueError, "inventory"):
            verify(self.root, self.manifest)

    def test_unsafe_path_fails(self):
        self.manifest["assets"][0]["target"] = "../escape"
        with self.assertRaisesRegex(ValueError, "Unsafe"):
            verify(self.root, self.manifest)
