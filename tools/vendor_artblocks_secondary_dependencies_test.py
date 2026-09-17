import hashlib
import json
import pathlib
import tempfile
import unittest
from unittest import mock

import vendor_artblocks_secondary_dependencies as vendor


class SecondaryDependencyFixtureTests(unittest.TestCase):
    def record(self, data, file="Hypertype/dependency.js"):
        return {"file": file, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(),
                "source": "https://cdn.lil.org/player/hypertype/dependency.js"}

    def test_default_manifest_keeps_dependency_only_in_test_fixtures(self):
        manifest = json.loads(vendor.DEFAULT_MANIFEST.read_text())
        self.assertEqual(manifest["secondaryAssets"], [])
        asset, = manifest["onDemandSecondaryAssets"]
        self.assertEqual(asset["cdnURL"], "https://cdn.lil.org/player/hypertype/dependency.js")
        self.assertEqual(asset["bytes"], 712587)
        self.assertEqual(asset["sha256"], "48d2613055cacdf43217ed43710990150ef2afaa15540c69d2b840d80fd4b6c8")
        self.assertEqual(vendor.DEFAULT_DESTINATION, vendor.REPOSITORY / "nft-player-iosTests/Fixtures")
        self.assertEqual(vendor.verify_or_restore(manifest["secondaryVendorFiles"], vendor.DEFAULT_DESTINATION), 0)
        self.assertFalse((vendor.REPOSITORY / "nft-player/Generators/newlibs/secondary-assets/hypertype/dependency.js").exists())

    def test_verification_does_not_fetch_or_change_invalid_fixture(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            target = root / "Hypertype/dependency.js"
            target.parent.mkdir()
            target.write_bytes(b"broken")
            with mock.patch.object(vendor, "download") as download:
                with self.assertRaises(ValueError):
                    vendor.verify_or_restore([self.record(b"expected")], root)
            download.assert_not_called()
            self.assertEqual(target.read_bytes(), b"broken")

    def test_fetch_restores_verified_fixture_at_selected_test_root(self):
        data = b"const fixture = true;"
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            with mock.patch.object(vendor, "download", return_value=data) as download:
                self.assertEqual(vendor.verify_or_restore([self.record(data)], root, fetch=True), 1)
            download.assert_called_once_with("https://cdn.lil.org/player/hypertype/dependency.js", len(data))
            self.assertEqual((root / "Hypertype/dependency.js").read_bytes(), data)
            with mock.patch.object(vendor, "download") as download:
                self.assertEqual(vendor.verify_or_restore([self.record(data)], root, fetch=True), 0)
            download.assert_not_called()

    def test_invalid_download_and_paths_never_publish(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            with mock.patch.object(vendor, "download", return_value=b"wrong"):
                with self.assertRaises(ValueError):
                    vendor.verify_or_restore([self.record(b"valid")], root, fetch=True)
            self.assertEqual(list(root.iterdir()), [])
            for file in ("../dependency.js", "/dependency.js"):
                with self.assertRaises(ValueError):
                    vendor.verify_or_restore([self.record(b"valid", file)], root, fetch=True)
            record = self.record(b"valid")
            with self.assertRaises(ValueError):
                vendor.verify_or_restore([record, record], root)


if __name__ == "__main__":
    unittest.main()
