import copy
import hashlib
import json
import unittest

from capture_artblocks_contract_parameters import parse_generator


class GeneratorSnapshotTests(unittest.TestCase):
    def setUp(self):
        self.source = 'window.artist = "unchanged";'
        self.job = {'sourceScriptSHA256': hashlib.sha256(self.source.encode()).hexdigest(),
                    'dependency': {'dependency_type': 'ONCHAIN', 'bytecode_address': '0x' + 'a' * 40}}
        self.token = {'id': '1000002', 'hash': '0x' + 'b' * 64}
        self.data = {'tokenId': self.token['id'], 'hash': self.token['hash'], 'externalAssetDependencies': [
            {'cid': '', 'dependency_type': 'ONCHAIN', 'bytecode_address': '0x' + 'a' * 40,
             'data': {'Palette': 'false', 'zero': '0', 'quote': '"\n\\', 'unicode': 'Växt'}}]}

    def html(self, data=None, suffix=''):
        return '<script>let tokenData = ' + json.dumps(data or self.data) + suffix + '</script><script>' + self.source + '</script>'

    def parse(self, html):
        return parse_generator(html, self.job, self.token, 'https://generator.artblocks.io/fixture')

    def test_preserves_exact_strings_and_unset_parameters(self):
        self.assertEqual(self.parse(self.html()), self.data['externalAssetDependencies'][0]['data'])
        self.data['externalAssetDependencies'][0]['data'] = {}
        self.assertEqual(self.parse(self.html(suffix=';')), {})

    def test_rejects_identity_or_dependency_mismatch(self):
        for mutate in (
            lambda data: data.update(tokenId='1000003'),
            lambda data: data.update(hash='0x' + 'c' * 64),
            lambda data: data['externalAssetDependencies'][0].update(bytecode_address='0x' + 'c' * 40),
            lambda data: data['externalAssetDependencies'].append(copy.deepcopy(data['externalAssetDependencies'][0])),
        ):
            data = copy.deepcopy(self.data)
            mutate(data)
            with self.assertRaises(ValueError):
                self.parse(self.html(data))

    def test_rejects_executable_or_duplicate_declarations(self):
        with self.assertRaises(ValueError):
            self.parse(self.html(suffix='; globalThis.fetch("https://example.invalid")'))
        with self.assertRaises(ValueError):
            self.parse(self.html() + self.html())

    def test_rejects_marker_and_coerced_values(self):
        for value in ('#web3call_contract#', None, {'value': 0}, {'value': False}, {'value': {'nested': 'data'}}):
            self.data['externalAssetDependencies'][0]['data'] = value
            with self.assertRaises(ValueError):
                self.parse(self.html())

    def test_rejects_changed_artist_source(self):
        with self.assertRaises(ValueError):
            self.parse(self.html().replace(self.source, self.source + ';'))


if __name__ == '__main__':
    unittest.main()
