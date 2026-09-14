import argparse
import concurrent.futures
import datetime
import hashlib
import json
import pathlib
import re
import time
import urllib.request


REPOSITORY = pathlib.Path(__file__).resolve().parent.parent
ENDPOINT = 'https://generator.artblocks.io'
DEFAULT_PREVIEW = REPOSITORY / 'Suggested Items/Suggested.bundle/Development/Good'
DEFAULT_EVIDENCE = REPOSITORY / 'build/artblocks-contract-parameters'


def timestamp():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def selected_projects(preview, compatibility, review_pass):
    items = json.loads((preview / 'items.json').read_text())
    active = set(json.loads(review_pass.read_text())['selectedIdentities'])
    known = json.loads(compatibility.read_text())['staticFirst']
    jobs = []
    for item in items:
        identity = item.get('reviewIdentity')
        if identity not in active or identity not in known:
            continue
        collection_id = item['address'] + item['collectionId']
        script = json.loads((preview / 'Scripts' / f'{collection_id}.json').read_text())
        tokens = json.loads((preview / 'Tokens' / f'{collection_id}.json').read_text())['items']
        expected = known[identity]['expectedDependency']
        dependencies = script.get('externalAssetDependencies')
        if len(dependencies or []) != 1 or dependencies[0].get('index') != 0:
            raise ValueError(f'Expected a single index-zero dependency: {identity}')
        dependency = dependencies[0]
        if expected['data'] != '#web3call_contract#' or any(dependency.get(key) != expected[key] for key in ('dependency_type', 'bytecode_address')):
            raise ValueError(f'Unexpected contract dependency: {identity}')
        chain, address, project = identity.split(':')
        if chain != '1' or address != item['address'] or script['abId'] != project or script['name'] != item['name'] or known[identity]['name'] != item['name']:
            raise ValueError(f'Project identity mismatch: {identity}')
        if not tokens or len({token['id'] for token in tokens}) != len(tokens):
            raise ValueError(f'Empty or duplicate token list: {identity}')
        for token in tokens:
            if not re.fullmatch(r'0|[1-9][0-9]*', token['id']) or int(token['id']) // 1000000 != int(project) or not re.fullmatch(r'0x[0-9a-f]{64}', token['hash']):
                raise ValueError(f'Invalid token: {identity}')
        jobs.append({'identity': identity, 'name': item['name'],
                     'sourceScriptSHA256': hashlib.sha256(script['value'].encode()).hexdigest(),
                     'dependency': {key: dependency[key] for key in ('index', 'dependency_type', 'bytecode_address')},
                     'tokens': [{key: token[key] for key in ('id', 'hash')} for token in tokens]})
    if {job['identity'] for job in jobs} != active.intersection(known):
        raise ValueError('Incomplete project coverage')
    return jobs


def parse_generator(html, job, token, url):
    matches = re.findall(r'<script[^>]*>\s*(?:let|const|var)\s+tokenData\s*=\s*([\s\S]*?)</script\s*>', html, re.I)
    if len(matches) != 1:
        raise ValueError(f'Expected one tokenData declaration: {url}')
    data, end = json.JSONDecoder().raw_decode(matches[0])
    if matches[0][end:].strip() not in ('', ';'):
        raise ValueError(f'Unexpected executable tokenData suffix: {url}')
    if data.get('tokenId') != token['id'] or data.get('hash') != token['hash']:
        raise ValueError(f'Token identity/hash mismatch: {url}')
    assets = data.get('externalAssetDependencies')
    if not isinstance(assets, list) or len(assets) != 1:
        raise ValueError(f'Unexpected dependency count: {url}')
    asset = assets[0]
    expected = job['dependency']
    if asset.get('dependency_type') != expected['dependency_type'] or asset.get('bytecode_address', '').lower() != expected['bytecode_address'] or asset.get('cid') != '':
        raise ValueError(f'Dependency identity mismatch: {url}')
    parameters = asset.get('data')
    if not isinstance(parameters, dict) or any(not isinstance(key, str) or not isinstance(value, str) for key, value in parameters.items()):
        raise ValueError(f'Invalid parameter object: {url}')
    scripts = re.findall(r'<script[^>]*>([\s\S]*?)</script\s*>', html, re.I)
    if not any(hashlib.sha256(script.encode()).hexdigest() == job['sourceScriptSHA256'] for script in scripts):
        raise ValueError(f'Artist source does not match bundled source: {url}')
    return parameters


def capture(job, token, evidence):
    chain, address, _ = job['identity'].split(':')
    url = f'{ENDPOINT}/{chain}/{address}/{token["id"]}'
    destination = evidence / 'raw' / f'{chain}-{address}-{token["id"]}.html'
    for attempt in range(4):
        try:
            request = urllib.request.Request(url, headers={'User-Agent': 'NFTPlayer-OfflineReview-Snapshot/1.0', 'Cache-Control': 'no-cache'})
            with urllib.request.urlopen(request, timeout=45) as response:
                if response.geturl() != url:
                    raise ValueError(f'Unexpected redirect: {response.geturl()}')
                html = response.read().decode('utf-8')
            break
        except Exception:
            if attempt == 3:
                raise
            time.sleep(2 ** attempt)
    fetched = timestamp()
    destination.write_text(html)
    parameters = parse_generator(html, job, token, url)
    record = {'hash': token['hash'], 'parameters': parameters, 'sourceURL': url, 'fetchedAt': fetched}
    destination.with_suffix('.json').write_text(json.dumps(record, ensure_ascii=False, indent=2) + '\n')
    return job['identity'], token['id'], record


def main():
    parser = argparse.ArgumentParser(description='Capture current Art Blocks PostParams for saved tokens in the active review pass. Does not change app resources.')
    parser.add_argument('--preview', type=pathlib.Path, default=DEFAULT_PREVIEW)
    parser.add_argument('--compatibility', type=pathlib.Path, default=REPOSITORY / 'tools/artblocks/review-compatibility.json')
    parser.add_argument('--review-pass', type=pathlib.Path, default=DEFAULT_PREVIEW.parent / 'review-pass.json')
    parser.add_argument('--evidence', type=pathlib.Path, default=DEFAULT_EVIDENCE)
    parser.add_argument('--output', type=pathlib.Path, default=DEFAULT_EVIDENCE / 'captured-parameters.json')
    args = parser.parse_args()
    jobs = selected_projects(args.preview, args.compatibility, args.review_pass)
    if not jobs:
        raise ValueError('No affected projects in the active review pass')
    started = timestamp()
    (args.evidence / 'raw').mkdir(parents=True, exist_ok=True)
    collections = {job['identity']: {key: job[key] for key in ('name', 'sourceScriptSHA256', 'dependency')} | {'tokens': {}} for job in jobs}
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as executor:
        futures = [executor.submit(capture, job, token, args.evidence) for job in jobs for token in job['tokens']]
        for index, future in enumerate(concurrent.futures.as_completed(futures), 1):
            identity, token_id, record = future.result()
            collections[identity]['tokens'][token_id] = record
            if index % 15 == 0 or index == len(futures):
                print(f'Validated {index}/{len(futures)} current token parameter snapshots', flush=True)
    for collection in collections.values():
        collection['tokens'] = dict(sorted(collection['tokens'].items(), key=lambda pair: int(pair[0])))
    snapshot = {'version': 1, 'source': ENDPOINT, 'capturedAt': started, 'collections': collections}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    temporary = args.output.with_name(args.output.name + '.tmp')
    temporary.write_text(json.dumps(snapshot, ensure_ascii=False, indent=2) + '\n')
    temporary.replace(args.output)
    print(f'Snapshot complete: {args.output}')


if __name__ == '__main__':
    main()
