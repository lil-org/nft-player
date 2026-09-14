import argparse
import copy
import datetime
import hashlib
import fcntl
import json
import os
from pathlib import Path
import stat
import tempfile


ROOT = Path(__file__).resolve().parents[1]
GROUPS = ('good', 'ok', 'hmm')
STATIC_JSON = 'tools/artblocks/reviews/deferred-static.json'
STATIC_MD = 'tools/artblocks/reviews/deferred-static.md'
APPROVED_JSON = 'tools/artblocks/reviews/approved.json'
REJECTED_JSON = 'tools/artblocks/rejected.json'
ARCHIVE = 'tools/artblocks/archive/sample-cleanup-2026-09-14'
ROOT_REPORTS = {'.DS_Store', 'README.md', 'inventory.json', 'pilot.json', 'size-estimate.json', 'summary.json', 'verification.json'}


def require(condition, message):
    if not condition:
        raise ValueError(message)


def digest(path):
    value = hashlib.sha256()
    with path.open('rb') as source:
        for block in iter(lambda: source.read(1024 * 1024), b''):
            value.update(block)
    return value.hexdigest()


def encoded(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + '\n').encode()


def atomic_write(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix='.' + path.name + '-', dir=path.parent)
    try:
        with os.fdopen(descriptor, 'wb') as stream:
            stream.write(data)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def immutable_write(path, data):
    if path.exists():
        require(path.is_file() and not path.is_symlink() and path.read_bytes() == data, f'Archive conflict: {path}')
    else:
        atomic_write(path, data)


def safe_path(root, relative):
    path = Path(relative)
    require(not path.is_absolute() and '..' not in path.parts and path.parts, f'Unsafe path: {relative}')
    current = root
    for part in path.parts:
        current = current / part
        require(not current.is_symlink(), f'Symlink refused: {current}')
    return current


def regular_files(directory):
    require(directory.is_dir() and not directory.is_symlink(), f'Expected directory: {directory}')
    files = {}
    directories = []
    for current, children, names in os.walk(directory, followlinks=False):
        for name in children:
            child = Path(current) / name
            require(not child.is_symlink() and child.is_dir(), f'Unexpected directory: {child}')
            directories.append(child.relative_to(directory).as_posix())
        for name in names:
            path = Path(current) / name
            info = path.lstat()
            require(stat.S_ISREG(info.st_mode), f'Expected regular file: {path}')
            files[path.relative_to(directory).as_posix()] = {'bytes': info.st_size, 'mtimeNS': info.st_mtime_ns}
    return files, sorted(directories)


def manifest_identity(path):
    require(path.is_file() and not path.is_symlink(), f'Missing collection manifest: {path}')
    value = json.loads(path.read_bytes())
    project = value['project']
    identity = f"{int(project['chain_id'])}:{project['contract_address'].lower()}:{int(project['project_id'])}"
    require(value.get('version') == 1 and value.get('identity') == identity, f'Conflicting manifest identity: {path}')
    require(project['id'] == project['contract_address'].lower() + '-' + str(int(project['project_id'])), f'Conflicting project: {path}')
    require(isinstance(value.get('tokens'), list), f'Invalid token manifest: {path}')
    return identity, value


def load_ledgers(root):
    documents = {name: json.loads(safe_path(root, name).read_bytes()) for name in (STATIC_JSON, APPROVED_JSON, REJECTED_JSON)}
    sets = {}
    for name, document in documents.items():
        rows = document['collections']
        identities = [row['identity'] for row in rows]
        require(len(identities) == len(set(identities)) == document['collectionCount'], f'Duplicate or incomplete ledger: {name}')
        sets[name] = set(identities)
    require(not (sets[STATIC_JSON] & sets[APPROVED_JSON] or sets[STATIC_JSON] & sets[REJECTED_JSON] or sets[APPROVED_JSON] & sets[REJECTED_JSON]), 'Overlapping decision ledgers')
    require(all(row.get('decision') == 'mb static' for row in documents[STATIC_JSON]['collections']), 'Invalid static decision')
    return documents, sets


def markdown(document):
    lines = ['# Collections deferred for static review', '',
             f"{document['collectionCount']} collections with {document['tokenCount']:,} saved samples, together in `samples/mb-static/`.", '',
             'Original decisions, notes, groups, and PNG alternatives are retained in [deferred-static.json](deferred-static.json). Previous locations are preserved in the sample-cleanup archive.', '',
             '| Collection | Decision pass | Saved tokens | Finder folder |', '| --- | --- | ---: | --- |']
    for row in document['collections']:
        name = row['name'].strip().replace('|', '\\|')
        source = row.get('sourcePassID', '')
        lines.append(f"| {name} | {source} | {len(row['samples'])} | [{Path(row['localCollectionFolder']).name}](../../../{row['localCollectionFolder']}) |")
    return ('\n'.join(lines) + '\n').encode()


def create_plan(root, enforce_totals=True):
    documents, identities = load_ledgers(root)
    static = documents[STATIC_JSON]
    static_rows = {row['identity']: row for row in static['collections']}
    known_rows = {row['identity']: row for document in documents.values() for row in document['collections']}
    samples = safe_path(root, 'samples')
    require(samples.is_dir(), 'Missing samples directory')
    for child in samples.iterdir():
        require(not child.is_symlink(), f'Symlink refused: {child}')
        if child.is_dir():
            require(child.name in GROUPS, f'Unexpected or occupied destination directory: {child}')
        else:
            require(child.name in ROOT_REPORTS and child.is_file(), f'Unexpected samples file: {child}')
    moves, removals, observed, metadata = [], [], set(), []
    for group in GROUPS:
        directory = safe_path(root, 'samples/' + group)
        require(directory.is_dir(), f'Missing original group: {directory}')
        for folder in sorted(directory.iterdir()):
            if folder.name == '.DS_Store' and folder.is_file() and not folder.is_symlink():
                metadata.append({'path': folder.relative_to(root).as_posix(), 'bytes': folder.stat().st_size, 'sha256': digest(folder), 'archive': False})
                continue
            files, directories = regular_files(folder)
            identity, manifest = manifest_identity(folder / 'manifest.json')
            require(identity not in observed, f'Duplicate identity: {identity}')
            observed.add(identity)
            keep = identity in identities[STATIC_JSON]
            require(keep or identity in identities[APPROVED_JSON] or identity in identities[REJECTED_JSON], f'Unknown collection: {identity}')
            recorded = known_rows[identity].get('localCollectionFolder')
            require(recorded == folder.relative_to(root).as_posix(), f'Folder differs from decision ledger: {folder}')
            nested = []
            for relative in directories:
                nested_path = folder / relative
                nested_identity, nested_manifest = manifest_identity(nested_path / 'manifest.json')
                require(nested_manifest['project'].get('directory') == nested_path.name, f'Unexpected nested folder name: {nested_path}')
                require(not keep and nested_identity in identities[REJECTED_JSON], f'Unexpected nested collection: {nested_path}')
                require(nested_identity not in observed, f'Duplicate identity: {nested_identity}')
                observed.add(nested_identity)
                nested.append({'path': relative, 'identity': nested_identity, 'manifestSHA256': digest(nested_path / 'manifest.json')})
            row = {'identity': identity, 'name': manifest['project']['name'], 'source': folder.relative_to(root).as_posix(),
                   'files': files, 'directories': directories, 'manifestSHA256': digest(folder / 'manifest.json'), 'nested': nested}
            if keep:
                expected = static_rows[identity]
                require(expected['localCollectionFolder'] == row['source'], f'Stale static folder: {identity}')
                require(len(expected['samples']) == len(manifest['tokens']), f'Static sample count mismatch: {identity}')
                for sample in expected['samples']:
                    relative = Path(sample['localPath'])
                    require(relative.parent.as_posix() == row['source'] and relative.name in files, f'Missing or unexpected static sample: {relative}')
                    require(any(entry['token']['token_id'] == sample['tokenId'] and entry.get('download', {}).get('file') == relative.name for entry in manifest['tokens']), f'Static token mismatch: {relative}')
                for relative in files:
                    files[relative]['sha256'] = digest(folder / relative)
                row['destination'] = 'samples/mb-static/' + folder.name
                moves.append(row)
            else:
                row['decision'] = 'approved' if identity in identities[APPROVED_JSON] else 'rejected'
                removals.append(row)
    require({r['identity'] for r in moves} == identities[STATIC_JSON], 'Missing static collections')
    require(identities[APPROVED_JSON].issubset(observed), 'Missing approved sample folders; inventory changed')
    require(len({r['destination'] for r in moves}) == len(moves), 'Destination collision')
    sample_count = sum(len(row['samples']) for row in static['collections'])
    require(sample_count == static['tokenCount'], 'Static token count mismatch')
    if enforce_totals:
        require((len(moves), sample_count, len(removals)) == (109, 2486, 396), 'Unexpected cleanup totals')
        require(sum(r['decision'] == 'approved' for r in removals) == 292, 'Unexpected approved removal count')
        require(sum(r['decision'] == 'rejected' for r in removals) == 104, 'Unexpected rejected removal count')
    for path in sorted(samples.iterdir()):
        if path.is_file():
            metadata.append({'path': path.relative_to(root).as_posix(), 'bytes': path.stat().st_size,
                             'sha256': digest(path), 'archive': path.name != '.DS_Store'})
    updated = copy.deepcopy(static)
    destinations = {r['identity']: r['destination'] for r in moves}
    for row in updated['collections']:
        row['localCollectionFolder'] = destinations[row['identity']]
        for sample in row['samples']:
            sample['localPath'] = row['localCollectionFolder'] + '/' + Path(sample['localPath']).name
    return {'version': 1, 'createdAt': datetime.datetime.now(datetime.timezone.utc).isoformat(),
            'inputs': {name: digest(root / name) for name in documents}, 'originalMarkdownSHA256': digest(root / STATIC_MD),
            'moves': moves, 'removals': removals, 'metadata': metadata, 'updatedStatic': updated,
            'summary': {'retainedCollections': len(moves), 'retainedSamples': sample_count,
                        'retainedBytes': sum(f['bytes'] for r in moves for f in r['files'].values()),
                        'removedTopLevelCollections': len(removals), 'removedNestedCollections': sum(len(r['nested']) for r in removals),
                        'removedSampleFiles': sum(len(r['files']) for r in removals),
                        'removedBytes': sum(f['bytes'] for r in removals for f in r['files'].values())}}


def verify_files(root, row, destination=False, partial=False):
    folder = safe_path(root, row['destination'] if destination else row['source'])
    if not folder.exists():
        require(partial, f'Missing folder: {folder}')
        return
    actual, directories = regular_files(folder)
    if destination and '.DS_Store' not in row['files']:
        actual.pop('.DS_Store', None)
    require(set(actual).issubset(row['files']) and set(directories).issubset(row['directories']), f'Unexpected contents: {folder}')
    if not partial:
        require(set(actual) == set(row['files']) and set(directories) == set(row['directories']), f'Changed file membership: {folder}')
    for name, info in actual.items():
        expected = row['files'][name]
        require(info['bytes'] == expected['bytes'], f'Changed file size: {folder / name}')
        if 'sha256' in expected:
            require(digest(folder / name) == expected['sha256'], f'Changed retained file: {folder / name}')
        else:
            require(info['mtimeNS'] == expected['mtimeNS'], f'Changed file timestamp: {folder / name}')
    for relative, identity, sha in [('manifest.json', row['identity'], row['manifestSHA256'])] + [(r['path'] + '/manifest.json', r['identity'], r['manifestSHA256']) for r in row['nested']]:
        path = folder / relative
        if path.exists():
            require(manifest_identity(path)[0] == identity and digest(path) == sha, f'Changed manifest: {path}')
        else:
            require(partial, f'Missing manifest: {path}')


def readonly_inputs(root, plan, allow_updated=False):
    for name, sha in plan['inputs'].items():
        actual = safe_path(root, name).read_bytes()
        if name == STATIC_JSON and allow_updated and actual == encoded(plan['updatedStatic']):
            continue
        require(hashlib.sha256(actual).hexdigest() == sha, f'Changed input ledger: {name}')
    md = safe_path(root, STATIC_MD).read_bytes()
    require(hashlib.sha256(md).hexdigest() == plan['originalMarkdownSHA256'] or allow_updated and md == markdown(plan['updatedStatic']), 'Changed static Markdown index')


def sample_readme(plan):
    return (f"# Static-review samples\n\n{plan['summary']['retainedCollections']} collections and {plan['summary']['retainedSamples']:,} original samples are in [mb-static](mb-static/).\n\nOpen this folder in Finder and sort by name. PNG and MP4 samples remain in their original formats. Each collection retains its manifest. Notes, previous decision provenance, and PNG alternative URLs are in ../tools/artblocks/reviews/deferred-static.json.\n\nThis is a reduced local review corpus, not the historical good/ok/hmm curation layout. Do not run --capture-curation against it. Verify it with `python3 tools/cleanup_artblocks_samples.py --check`.\n").encode()


def current_static_plan(root, original):
    journal_path = safe_path(root, 'tools/artblocks/reviews/finder-deletions.json')
    if not journal_path.exists():
        return original
    journal = json.loads(journal_path.read_bytes())
    require(journal.get('version') == 1 and journal.get('collectionCount') == len(journal['collections']), 'Invalid Finder deletion record')
    require(hashlib.sha256(encoded(original['updatedStatic'])).hexdigest() == journal.get('previousStaticSHA256'), 'Finder decisions have a different source index')
    previous = {row['identity']: row for row in original['updatedStatic']['collections']}
    deleted = set()
    rejected = json.loads(safe_path(root, REJECTED_JSON).read_bytes())
    rejection_rows = {row['identity']: row for row in rejected['collections']}
    require(len(rejection_rows) == len(rejected['collections']) == rejected['collectionCount'], 'Invalid rejection ledger')
    for row in journal['collections']:
        identity = row['identity']
        require(identity in previous and identity not in deleted, 'Unexpected or duplicate Finder deletion')
        prior = previous[identity]
        require(row.get('decision') == 'no' and row.get('status') == 'deleted' and row.get('previousDecision') == 'mb static', 'Invalid Finder decision')
        require(all(row.get(key) == prior.get(key) for key in ('name', 'group', 'note', 'sourcePassID', 'localCollectionFolder')), 'Finder decision changed original metadata')
        require(row.get('sampleCount') == len(prior['samples']), 'Finder deletion sample count mismatch')
        require(not safe_path(root, prior['localCollectionFolder']).exists(), 'A recorded deleted collection is still present')
        rejection = rejection_rows.get(identity, {})
        require(all(rejection.get(key) == value for key, value in row.items()) and rejection.get('source') == 'finder-static-review', 'Finder deletion missing from rejection ledger')
        deleted.add(identity)
    before_rejected = copy.deepcopy(rejected)
    before_rejected['collections'] = [row for row in rejected['collections'] if row['identity'] not in deleted]
    before_rejected['collectionCount'] = len(before_rejected['collections'])
    require(before_rejected.get('sources', {}).pop('finderStatic', None) == len(deleted), 'Wrong Finder rejection count')
    require(hashlib.sha256(encoded(before_rejected)).hexdigest() == original['inputs'][REJECTED_JSON], 'Earlier rejection records changed')
    current = copy.deepcopy(original)
    current['moves'] = [row for row in current['moves'] if row['identity'] not in deleted]
    current['updatedStatic']['collections'] = [row for row in current['updatedStatic']['collections'] if row['identity'] not in deleted]
    current['updatedStatic']['collectionCount'] = len(current['moves'])
    current['updatedStatic']['tokenCount'] = sum(len(row['samples']) for row in current['updatedStatic']['collections'])
    require(safe_path(root, STATIC_JSON).read_bytes() == encoded(current['updatedStatic']), 'Current static index does not match recorded deletions')
    current['inputs'][REJECTED_JSON] = digest(root / REJECTED_JSON)
    current['summary'].update(retainedCollections=len(current['moves']), retainedSamples=current['updatedStatic']['tokenCount'],
                              retainedBytes=sum(item['bytes'] for row in current['moves'] for item in row['files'].values()),
                              laterFinderDeletions=len(deleted))
    return current


def check(root, archive):
    plan_path = safe_path(root, archive + '/plan.json')
    plan = json.loads(plan_path.read_bytes())
    state = json.loads(safe_path(root, archive + '/progress.json').read_bytes())
    require(state['planSHA256'] == digest(plan_path) and state.get('complete'), 'Cleanup is not complete')
    original_plan = plan
    plan = current_static_plan(root, plan)
    readonly_inputs(root, plan, allow_updated=True)
    require((root / STATIC_JSON).read_bytes() == encoded(plan['updatedStatic']), 'Static index not updated')
    require((root / STATIC_MD).read_bytes() == markdown(plan['updatedStatic']), 'Static Markdown not updated')
    verify_retained(root, plan)
    require(not any(safe_path(root, r['source']).exists() for r in plan['removals']), 'Removal still present')
    require(not any(safe_path(root, 'samples/' + group).exists() for group in GROUPS), 'Old group still present')
    require({p.name for p in (root / 'samples').iterdir()} <= {'mb-static', 'README.md', '.DS_Store'}, 'Unexpected samples root contents')
    require((root / 'samples/README.md').read_bytes() == sample_readme(plan), 'Stale samples README')
    for item in plan['metadata']:
        if item['archive']:
            target = safe_path(root, archive + '/local-reports/' + item['path'])
            require(target.is_file() and digest(target) == item['sha256'], f'Missing report archive: {target}')
    for name, sha in [(STATIC_JSON, original_plan['inputs'][STATIC_JSON]), (STATIC_MD, original_plan['originalMarkdownSHA256'])]:
        require(digest(safe_path(root, archive + '/' + Path(name).name)) == sha, 'Missing original static index archive')
    return plan['summary']


def verify_retained(root, plan):
    folder = safe_path(root, 'samples/mb-static')
    require(folder.is_dir(), 'Missing mb-static directory')
    expected = {Path(row['destination']).name for row in plan['moves']}
    actual = {p.name for p in folder.iterdir()}
    if '.DS_Store' in actual:
        finder_metadata = folder / '.DS_Store'
        require(finder_metadata.is_file() and not finder_metadata.is_symlink(), 'Unexpected Finder metadata entry')
        actual.remove('.DS_Store')
    require(actual == expected, 'Unexpected or missing mb-static folders')
    for row in plan['moves']:
        require(not safe_path(root, row['source']).exists(), f'Both source and destination exist: {row["identity"]}')
        verify_files(root, row, destination=True)
    for row in plan['updatedStatic']['collections']:
        for sample in row['samples']:
            require(safe_path(root, sample['localPath']).is_file(), 'Broken static sample path')


def apply(root, archive, enforce_totals=True, checkpoint=lambda event: None):
    lock_path = safe_path(root, 'build/artblocks-sample-cleanup.lock')
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    with lock_path.open('a') as lock:
        try:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError as error:
            raise ValueError('Another sample cleanup is running') from error
        return apply_locked(root, archive, enforce_totals, checkpoint)


def apply_locked(root, archive, enforce_totals, checkpoint):
    archive_path = safe_path(root, archive)
    plan_path = archive_path / 'plan.json'
    state_path = archive_path / 'progress.json'
    if plan_path.exists():
        plan = json.loads(plan_path.read_bytes())
        require(state_path.is_file(), 'Missing cleanup journal; refusing to infer deletion permission')
        state = json.loads(state_path.read_bytes())
        require(state['planSHA256'] == digest(plan_path), 'Cleanup journal/plan mismatch')
    else:
        require(not archive_path.exists(), f'Unrecognized cleanup archive: {archive_path}')
        plan = create_plan(root, enforce_totals)
        archive_path.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='.' + archive_path.name + '-preparing-', dir=archive_path.parent) as temporary:
            staging = Path(temporary) / 'archive'
            staging.mkdir()
            for name in (STATIC_JSON, STATIC_MD):
                immutable_write(staging / Path(name).name, (root / name).read_bytes())
            for item in plan['metadata']:
                if item['archive']:
                    immutable_write(staging / 'local-reports' / item['path'], (root / item['path']).read_bytes())
            immutable_write(staging / 'plan.json', encoded(plan))
            state = {'version': 1, 'planSHA256': digest(staging / 'plan.json'), 'moved': [], 'deleting': [], 'deleted': [], 'complete': False}
            atomic_write(staging / 'progress.json', encoded(state))
            os.rename(staging, archive_path)
    if state['complete']:
        return check(root, archive)
    readonly_inputs(root, plan, allow_updated=True)
    for name, sha in [(STATIC_JSON, plan['inputs'][STATIC_JSON]), (STATIC_MD, plan['originalMarkdownSHA256'])]:
        require(digest(safe_path(root, archive + '/' + Path(name).name)) == sha, 'Original index archive is missing or changed')
    for item in plan['metadata']:
        if item['archive']:
            require(digest(safe_path(root, archive + '/local-reports/' + item['path'])) == item['sha256'], 'Local report archive is missing or changed')
    destination = safe_path(root, 'samples/mb-static')
    destination.mkdir(exist_ok=True)
    for row in plan['moves']:
        source, target = safe_path(root, row['source']), safe_path(root, row['destination'])
        require(not (source.exists() and target.exists()), f'Destination collision: {target}')
        if source.exists():
            verify_files(root, row)
            os.rename(source, target)
        else:
            verify_files(root, row, destination=True)
        if row['identity'] not in state['moved']:
            state['moved'].append(row['identity'])
            atomic_write(state_path, encoded(state))
        checkpoint('moved')
    verify_retained(root, plan)
    checkpoint('retained-verified')
    for row in plan['removals']:
        readonly_inputs(root, plan, allow_updated=True)
        partial = row['identity'] in state['deleting']
        verify_files(root, row, partial=partial)
        if not partial:
            state['deleting'].append(row['identity'])
            atomic_write(state_path, encoded(state))
        folder = safe_path(root, row['source'])
        if folder.exists():
            files, directories = regular_files(folder)
            ordered = sorted(files, key=lambda name: (Path(name).name == 'manifest.json', name))
            for name in ordered:
                target = safe_path(root, row['source'] + '/' + name)
                info = target.lstat()
                expected = row['files'][name]
                require(stat.S_ISREG(info.st_mode) and info.st_size == expected['bytes'] and info.st_mtime_ns == expected['mtimeNS'], f'File changed during deletion: {target}')
                target.unlink()
                checkpoint('deleted-file')
            for relative in sorted(directories, key=lambda name: (-len(Path(name).parts), name)):
                safe_path(root, row['source'] + '/' + relative).rmdir()
            folder.rmdir()
        if row['identity'] not in state['deleted']:
            state['deleted'].append(row['identity'])
            atomic_write(state_path, encoded(state))
        checkpoint('deleted-folder')
    for item in plan['metadata']:
        path = safe_path(root, item['path'])
        if path.exists():
            if item['path'] == 'samples/README.md' and path.read_bytes() == sample_readme(plan):
                continue
            require(path.is_file() and digest(path) == item['sha256'], f'Changed local report: {path}')
            path.unlink()
    for group in GROUPS:
        path = safe_path(root, 'samples/' + group)
        if path.exists():
            path.rmdir()
    atomic_write(root / STATIC_JSON, encoded(plan['updatedStatic']))
    atomic_write(root / STATIC_MD, markdown(plan['updatedStatic']))
    atomic_write(root / 'samples/README.md', sample_readme(plan))
    checkpoint('published')
    state['complete'] = True
    state['completedAt'] = datetime.datetime.now(datetime.timezone.utc).isoformat()
    atomic_write(state_path, encoded(state))
    result = check(root, archive)
    immutable_write(archive_path / 'result.json', encoded(result))
    return result


def main():
    parser = argparse.ArgumentParser(description='Retain only verified mb-static sample folders; default is a read-only dry run.')
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--apply', action='store_true')
    mode.add_argument('--check', action='store_true')
    args = parser.parse_args()
    if args.check:
        result = check(ROOT, ARCHIVE)
    elif args.apply:
        result = apply(ROOT, ARCHIVE)
    elif (ROOT / ARCHIVE / 'plan.json').exists():
        result = current_static_plan(ROOT, json.loads((ROOT / ARCHIVE / 'plan.json').read_bytes()))['summary']
    else:
        result = create_plan(ROOT)['summary']
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
