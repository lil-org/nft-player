import hashlib
import pathlib
import tempfile
from unittest import mock
import unittest
from capture_artblocks_production import validate_tokens, capture_project, validate_capture_checksums, validate_parameter_record, save


class CaptureTests(unittest.TestCase):
    def setUp(self):
        self.address = '0x' + '1' * 40
        self.project = {'identity': f'1:{self.address}:2', 'name': 'Test'}
        self.token = {'id': f'{self.address}-2000000', 'chain_id': 1, 'contract_address': self.address, 'project_id': f'{self.address}-2', 'token_id': '2000000', 'invocation': 0, 'hash': '0x' + 'a' * 64}

    def test_complete_capture_and_reviewed_hash(self):
        validate_tokens(self.project, [self.token], 1, {'2000000': {'hash': self.token['hash']}})

    def test_missing_duplicate_wrong_chain_or_changed_reviewed_hash_fail(self):
        for tokens, cutoff, reviewed in [([], 1, {}), ([self.token, self.token], 2, {}), ([dict(self.token, chain_id=2)], 1, {}), ([self.token], 1, {'2000000': {'hash': '0x' + 'b' * 64}}), ([self.token], 1, {'2000001': {'hash': self.token['hash']}})]:
            with self.assertRaises(ValueError):
                validate_tokens(self.project, tokens, cutoff, reviewed)

    def test_autorad_requires_new_reference_geometry(self):
        project = dict(self.project, name='autoRAD')
        with self.assertRaisesRegex(ValueError, 'reference geometry'):
            validate_tokens(project, [self.token], 1, {})
        token = dict(self.token, image={'metadata': {'width': 1600, 'height': 900}})
        validate_tokens(project, [token], 1, {})
        validate_tokens(project, [self.token], 1, {'2000000': {'hash': self.token['hash']}})

    def test_offline_resume_rejects_stale_parameter_source_or_dependency_without_refetching(self):
        dependency = {'index': 0, 'dependency_type': 'ONCHAIN', 'bytecode_address': '0x' + '2' * 40}
        script = {'value': 'const immutableArtistSource = true;', 'externalAssetDependencies': [dependency]}
        record = {'hash': self.token['hash'], 'parameters': {'value': 'frozen'}, 'sourceScriptSHA256': hashlib.sha256(script['value'].encode()).hexdigest(), 'dependency': dependency, 'sourceURL': f'https://generator.artblocks.io/1/{self.address}/2000000'}
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            archive = root / 'archive'
            capture = root / 'capture'
            stem = self.project['identity'].replace(':', '-')
            save(archive / 'Scripts/fixture.json', script)
            save(archive / 'Tokens/fixture.json', {'items': []})
            save(capture / f'tokens/{stem}.json', [self.token])
            parameter_path = capture / f'parameters/{stem}.json'
            with mock.patch('capture_artblocks_production.ARCHIVE', archive), mock.patch('capture_artblocks_production.request', side_effect=AssertionError('Offline resume attempted a fetch')):
                for field, value in [('sourceScriptSHA256', '0' * 64), ('dependency', dict(dependency, bytecode_address='0x' + '3' * 40)), ('sourceURL', 'https://wrong.invalid')]:
                    with self.subTest(field=field):
                        save(parameter_path, {'2000000': dict(record, **{field: value})})
                        before = parameter_path.read_bytes()
                        with self.assertRaisesRegex(ValueError, 'Frozen parameter'):
                            capture_project(dict(self.project, collectionId='fixture'), 1, capture, True)
                        self.assertEqual(parameter_path.read_bytes(), before)
                save(parameter_path, {'2000000': record})
                self.assertEqual(capture_project(dict(self.project, collectionId='fixture'), 1, capture, True), ('Test', 1))

    def test_capture_checksums_require_every_consumed_file(self):
        required = {'cutoff.json', 'tokens/project.json', 'parameters/project.json'}
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            for relative in required:
                save(root / relative, {})
            files = {relative: hashlib.sha256((root / relative).read_bytes()).hexdigest() for relative in required}
            validate_capture_checksums(root, {'files': files}, required)
            for missing in required:
                with self.subTest(missing=missing), self.assertRaisesRegex(ValueError, 'membership'):
                    validate_capture_checksums(root, {'files': {key: value for key, value in files.items() if key != missing}}, required)
            with self.assertRaisesRegex(ValueError, 'membership'):
                validate_capture_checksums(root, {'files': dict(files, unexpected='0' * 64)}, required)

    def test_reviewed_parameter_cache_preserves_values_and_recorded_origin(self):
        job = {'identity': self.project['identity']}
        old = {'previewContractParameters': {'value': 'original'}}
        record = {'hash': self.token['hash'], 'parameters': old['previewContractParameters'], 'source': 'reviewed-frozen-record'}
        validate_parameter_record(job, self.token, record, old)
        for changes in [{'parameters': {'value': 'changed'}}, {'source': 'uncertain'}, {'hash': '0x' + 'b' * 64}]:
            with self.assertRaises(ValueError):
                validate_parameter_record(job, self.token, dict(record, **changes), old)


if __name__ == '__main__':
    unittest.main()
