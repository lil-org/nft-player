import copy
import json
from pathlib import Path
import tempfile
import unittest

import cleanup_artblocks_samples as cleanup


class CleanupTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for group in cleanup.GROUPS:
            (self.root / 'samples' / group).mkdir(parents=True)
        self.static = self.collection('static', 'ok', 1, keep=True)
        self.approved = self.collection('approved', 'good', 2)
        self.rejected = self.collection('rejected', 'hmm', 3)
        for name, rows in [(cleanup.STATIC_JSON, [self.static]), (cleanup.APPROVED_JSON, [self.approved]), (cleanup.REJECTED_JSON, [self.rejected])]:
            data = {'version': 1, 'collectionCount': len(rows), 'collections': rows}
            if name == cleanup.REJECTED_JSON:
                data['sources'] = {'initial': len(rows)}
            if name == cleanup.STATIC_JSON:
                data['tokenCount'] = 1
                data['sourceReviews'] = {'pass-1': 'original-fingerprint'}
            self.write(name, cleanup.encoded(data))
        self.write(cleanup.STATIC_MD, b'# Original index\n')
        self.write('samples/README.md', b'Original sample README\n')
        self.write('samples/inventory.json', b'{"historical":true}\n')
        self.before_static = (self.root / cleanup.STATIC_JSON).read_bytes()
        self.before_approved = (self.root / cleanup.APPROVED_JSON).read_bytes()
        self.before_rejected = (self.root / cleanup.REJECTED_JSON).read_bytes()
        self.keep_bytes = {p.name: p.read_bytes() for p in (self.root / self.static['localCollectionFolder']).iterdir()}

    def write(self, relative, data):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)

    def collection(self, name, group, project_id, keep=False, parent=None):
        address = '0x' + str(project_id) * 40
        identity = f'1:{address}:{project_id}'
        basename = f'{name}--1--{address}--{project_id}'
        relative = (parent + '/' if parent else 'samples/' + group + '/') + basename
        token_id = str(project_id * 1000000)
        file = token_id + '.png'
        manifest = {'version': 1, 'identity': identity,
                    'project': {'id': f'{address}-{project_id}', 'chain_id': 1, 'contract_address': address,
                                'project_id': str(project_id), 'name': name, 'directory': basename},
                    'tokens': [{'token': {'token_id': token_id}, 'download': {'file': file}}]}
        self.write(relative + '/manifest.json', cleanup.encoded(manifest))
        self.write(relative + '/' + file, ('PNG fixture ' + name).encode())
        return {'identity': identity, 'name': name, 'group': group, 'decision': 'mb static' if keep else 'yes',
                'sourcePassID': 'pass-1', 'note': 'Review note 雪\nsecond line', 'localCollectionFolder': relative,
                'samples': [{'tokenId': token_id, 'localPath': relative + '/' + file, 'fallbackImageURL': 'https://example.test/' + file}]}

    def apply(self, callback=lambda event: None):
        return cleanup.apply(self.root, cleanup.ARCHIVE, enforce_totals=False, checkpoint=callback)

    def assert_complete(self):
        result = cleanup.check(self.root, cleanup.ARCHIVE)
        self.assertEqual(result['retainedCollections'], 1)
        self.assertEqual(result['removedTopLevelCollections'], 2)
        new = self.root / 'samples/mb-static' / Path(self.static['localCollectionFolder']).name
        self.assertEqual({p.name: p.read_bytes() for p in new.iterdir()}, self.keep_bytes)
        for row in [self.approved, self.rejected]:
            self.assertFalse((self.root / row['localCollectionFolder']).exists())
        updated = json.loads((self.root / cleanup.STATIC_JSON).read_bytes())['collections'][0]
        restored = copy.deepcopy(updated)
        restored['localCollectionFolder'] = self.static['localCollectionFolder']
        restored['samples'][0]['localPath'] = self.static['samples'][0]['localPath']
        self.assertEqual(restored, self.static)
        self.assertEqual((self.root / cleanup.APPROVED_JSON).read_bytes(), self.before_approved)
        self.assertEqual((self.root / cleanup.REJECTED_JSON).read_bytes(), self.before_rejected)
        self.assertEqual((self.root / cleanup.ARCHIVE / 'deferred-static.json').read_bytes(), self.before_static)
        self.assertEqual((self.root / cleanup.ARCHIVE / 'local-reports/samples/inventory.json').read_bytes(), b'{"historical":true}\n')

    def test_dry_run_does_not_change_files(self):
        before = {p.relative_to(self.root): p.read_bytes() for p in self.root.rglob('*') if p.is_file()}
        plan = cleanup.create_plan(self.root, enforce_totals=False)
        self.assertEqual(plan['summary']['retainedSamples'], 1)
        self.assertEqual(before, {p.relative_to(self.root): p.read_bytes() for p in self.root.rglob('*') if p.is_file()})

    def test_cleanup_preserves_bytes_metadata_and_repeated_apply(self):
        self.apply()
        self.assert_complete()
        self.apply()
        self.assert_complete()

    def test_verification_allows_finder_metadata_but_rejects_other_new_files(self):
        self.apply()
        destination = 'samples/mb-static/' + Path(self.static['localCollectionFolder']).name
        self.write('samples/mb-static/.DS_Store', b'Finder folder preferences')
        self.write(destination + '/.DS_Store', b'Finder collection preferences')
        cleanup.check(self.root, cleanup.ARCHIVE)
        self.write(destination + '/unexpected.png', b'unknown sample')
        with self.assertRaises(ValueError):
            cleanup.check(self.root, cleanup.ARCHIVE)

    def test_interruption_after_move_resumes(self):
        def interrupt(event):
            if event == 'moved':
                raise RuntimeError('interrupted')
        with self.assertRaises(RuntimeError):
            self.apply(interrupt)
        self.assertTrue((self.root / self.approved['localCollectionFolder']).exists())
        self.apply()
        self.assert_complete()

    def test_interruption_during_file_deletion_resumes(self):
        def interrupt(event):
            if event == 'deleted-file':
                raise RuntimeError('interrupted')
        with self.assertRaises(RuntimeError):
            self.apply(interrupt)
        self.apply()
        self.assert_complete()

    def test_interruption_after_publication_resumes(self):
        def interrupt(event):
            if event == 'published':
                raise RuntimeError('interrupted')
        with self.assertRaises(RuntimeError):
            self.apply(interrupt)
        self.apply()
        self.assert_complete()

    def test_retained_corruption_blocks_deletion(self):
        def interrupt(event):
            if event == 'moved':
                raise RuntimeError('interrupted')
        with self.assertRaises(RuntimeError):
            self.apply(interrupt)
        target = self.root / 'samples/mb-static' / Path(self.static['localCollectionFolder']).name / Path(self.static['samples'][0]['localPath']).name
        target.write_bytes(b'corrupt')
        with self.assertRaises(ValueError):
            self.apply()
        self.assertTrue((self.root / self.approved['localCollectionFolder']).exists())

    def test_changed_removal_and_new_files_are_refused(self):
        def interrupt(event):
            if event == 'retained-verified':
                raise RuntimeError('interrupted')
        with self.assertRaises(RuntimeError):
            self.apply(interrupt)
        self.write(self.approved['localCollectionFolder'] + '/new-user-file.txt', b'unexpected')
        with self.assertRaises(ValueError):
            self.apply()
        self.assertTrue((self.root / self.approved['samples'][0]['localPath']).exists())

    def test_symlink_is_refused(self):
        (self.root / self.approved['localCollectionFolder'] / 'unsafe').symlink_to('/tmp')
        with self.assertRaises(ValueError):
            cleanup.create_plan(self.root, enforce_totals=False)

    def test_unknown_identity_is_refused(self):
        self.collection('unknown', 'good', 4)
        with self.assertRaises(ValueError):
            cleanup.create_plan(self.root, enforce_totals=False)

    def test_destination_collision_is_refused(self):
        (self.root / 'samples/mb-static').mkdir()
        with self.assertRaises(ValueError):
            self.apply()

    def test_duplicate_identity_is_refused(self):
        import shutil
        original = self.root / self.approved['localCollectionFolder']
        shutil.copytree(original, self.root / 'samples/ok' / original.name)
        with self.assertRaises(ValueError):
            cleanup.create_plan(self.root, enforce_totals=False)

    def test_manifest_project_mismatch_is_refused(self):
        p = self.root / self.approved['localCollectionFolder'] / 'manifest.json'
        d = json.loads(p.read_bytes())
        d['project']['project_id'] = '99'
        p.write_bytes(cleanup.encoded(d))
        with self.assertRaises(ValueError):
            self.apply()

    def test_recorded_folder_with_trailing_space_is_supported(self):
        original = self.root / self.rejected['localCollectionFolder']
        original.rename(original.with_name(original.name + ' '))
        self.rejected['localCollectionFolder'] += ' '
        self.rejected['samples'][0]['localPath'] = self.rejected['localCollectionFolder'] + '/' + Path(self.rejected['samples'][0]['localPath']).name
        d = json.loads((self.root / cleanup.REJECTED_JSON).read_bytes())
        d['collections'] = [self.rejected]
        self.write(cleanup.REJECTED_JSON, cleanup.encoded(d))
        self.before_rejected = (self.root / cleanup.REJECTED_JSON).read_bytes()
        self.apply()
        self.assert_complete()

    def test_nested_rejected_collection_is_explicitly_recorded(self):
        nested = self.collection('nested-rejected', 'good', 4, parent=self.approved['localCollectionFolder'])
        d = json.loads((self.root / cleanup.REJECTED_JSON).read_bytes())
        d['collections'].append(nested)
        d['collectionCount'] += 1
        self.write(cleanup.REJECTED_JSON, cleanup.encoded(d))
        self.before_rejected = (self.root / cleanup.REJECTED_JSON).read_bytes()
        plan = cleanup.create_plan(self.root, enforce_totals=False)
        self.assertEqual(plan['summary']['removedNestedCollections'], 1)
        self.apply()
        self.assert_complete()

    def test_nested_folder_in_retained_collection_is_refused(self):
        self.collection('unknown-child', 'good', 4, parent=self.static['localCollectionFolder'])
        with self.assertRaises(ValueError):
            self.apply()

    def test_confirmed_finder_deletion_updates_verification_without_rewriting_cleanup_history(self):
        import hashlib
        import shutil
        self.apply()
        original_plan = (self.root / cleanup.ARCHIVE / 'plan.json').read_bytes()
        old_bytes = (self.root / cleanup.STATIC_JSON).read_bytes()
        previous = json.loads(old_bytes)
        prior = previous['collections'][0]
        shutil.rmtree(self.root / prior['localCollectionFolder'])
        row = {key: prior[key] for key in ('identity', 'name', 'group', 'note', 'sourcePassID', 'localCollectionFolder')}
        row.update(decision='no', status='deleted', previousDecision='mb static', sampleCount=1)
        journal = {'version': 1, 'collectionCount': 1, 'previousStaticSHA256': hashlib.sha256(old_bytes).hexdigest(), 'collections': [row]}
        self.write('tools/artblocks/reviews/finder-deletions.json', cleanup.encoded(journal))
        rejected = json.loads((self.root / cleanup.REJECTED_JSON).read_bytes())
        rejected['collections'].append(dict(row, source='finder-static-review'))
        rejected['collectionCount'] += 1
        rejected['sources']['finderStatic'] = 1
        self.write(cleanup.REJECTED_JSON, cleanup.encoded(rejected))
        previous.update(collections=[], collectionCount=0, tokenCount=0)
        self.write(cleanup.STATIC_JSON, cleanup.encoded(previous))
        self.write(cleanup.STATIC_MD, cleanup.markdown(previous))
        current = cleanup.current_static_plan(self.root, json.loads(original_plan))
        self.write('samples/README.md', cleanup.sample_readme(current))
        result = cleanup.check(self.root, cleanup.ARCHIVE)
        self.assertEqual(result['retainedCollections'], 0)
        self.assertEqual(result['laterFinderDeletions'], 1)
        self.assertEqual((self.root / cleanup.ARCHIVE / 'plan.json').read_bytes(), original_plan)
        journal['collections'][0]['note'] = 'Changed historical note'
        self.write('tools/artblocks/reviews/finder-deletions.json', cleanup.encoded(journal))
        with self.assertRaises(ValueError):
            cleanup.check(self.root, cleanup.ARCHIVE)

    def test_unrecorded_missing_folder_is_not_treated_as_a_decision(self):
        import shutil
        self.apply()
        destination = self.root / 'samples/mb-static' / Path(self.static['localCollectionFolder']).name
        shutil.rmtree(destination)
        with self.assertRaises(ValueError):
            cleanup.check(self.root, cleanup.ARCHIVE)

    def test_full_png_inventory_preserves_original_checksums_and_allows_only_declared_additions(self):
        import hashlib
        self.apply()
        plan = json.loads((self.root / cleanup.ARCHIVE / 'plan.json').read_bytes())
        row = plan['moves'][0]
        original_file = Path(self.static['samples'][0]['localPath']).name
        original_data = row['files'][original_file]
        additional = b'additional PNG fixture'
        new_file = '1000001.png'
        self.write(row['destination'] + '/' + new_file, additional)
        inventory = {'version': 1, 'status': 'complete', 'sourceIndexSHA256': cleanup.digest(self.root / cleanup.STATIC_JSON),
                     'sourceRejectedSHA256': cleanup.digest(self.root / cleanup.REJECTED_JSON),
                     'collections': [{'identity': row['identity'], 'name': row['name'], 'folder': row['destination'],
                                      'invocationCutoff': 2, 'originalManifestSHA256': row['manifestSHA256'],
                                      'tokens': [{'id': '1000000', 'file': original_file, 'original': True, 'status': 'downloaded',
                                                  'download': dict(original_data, extension='png')},
                                                 {'id': '1000001', 'file': new_file, 'original': False, 'status': 'downloaded',
                                                  'download': {'extension': 'png', 'bytes': len(additional), 'sha256': hashlib.sha256(additional).hexdigest()}}]}]}
        self.write('tools/artblocks/reviews/static-downloads.json', cleanup.encoded(inventory))
        expanded = cleanup.include_static_downloads(self.root, plan)
        self.write(cleanup.STATIC_MD, cleanup.markdown(plan['updatedStatic'], expanded['downloadsSummary']))
        self.write('samples/README.md', cleanup.sample_readme(expanded))
        self.assertEqual(cleanup.check(self.root, cleanup.ARCHIVE)['retainedSamples'], 2)
        inventory['collections'][0]['tokens'][0]['download']['sha256'] = 'f' * 64
        self.write('tools/artblocks/reviews/static-downloads.json', cleanup.encoded(inventory))
        with self.assertRaises(ValueError):
            cleanup.check(self.root, cleanup.ARCHIVE)

    def test_input_ledger_change_stops_resume(self):
        def interrupt(event):
            if event == 'retained-verified':
                raise RuntimeError('interrupted')
        with self.assertRaises(RuntimeError):
            self.apply(interrupt)
        self.write(cleanup.REJECTED_JSON, b'{}')
        with self.assertRaises(ValueError):
            self.apply()
        self.assertTrue((self.root / self.approved['localCollectionFolder']).exists())


if __name__ == '__main__':
    unittest.main()
