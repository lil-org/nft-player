#!/usr/bin/env python3
import argparse
import concurrent.futures
import datetime
import hashlib
import json
import pathlib
import time
import threading
import urllib.request
from capture_artblocks_contract_parameters import parse_generator

ROOT = pathlib.Path(__file__).resolve().parent.parent
ARCHIVE = ROOT / 'tools/artblocks/archive/pass-5/Development/Good'
CAPTURE = ROOT / 'tools/artblocks/production/capture'
API = 'https://data.artblocks.io/v1/graphql'
PAGE_SIZE = 500
API_LOCK = threading.Lock()
API_NEXT = 0


def read(path):
    return json.loads(path.read_text())


def save(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + '.tmp')
    temporary.write_text(json.dumps(data, ensure_ascii=False, separators=(',', ':')) + '\n')
    temporary.replace(path)


def now():
    return datetime.datetime.now(datetime.timezone.utc).isoformat()


def request(url, data=None):
    for attempt in range(6):
        try:
            payload = None if data is None else json.dumps(data).encode()
            req = urllib.request.Request(url, data=payload, headers={'Content-Type': 'application/json', 'User-Agent': 'NFTPlayer-Frozen-Capture/1.0'})
            with urllib.request.urlopen(req, timeout=90) as response:
                return response.read().decode()
        except Exception:
            if attempt == 5:
                raise
            time.sleep(min(30, 2 ** attempt))


def graphql(query, variables):
    global API_NEXT
    for attempt in range(6):
        with API_LOCK:
            delay = max(0, API_NEXT - time.monotonic())
            API_NEXT = time.monotonic() + delay + 0.8
        time.sleep(delay)
        value = json.loads(request(API, {'query': query, 'variables': variables}))
        if not value.get('errors'):
            return value['data']
        if attempt == 5 or any(e.get('extensions', {}).get('code') != 'rate-limit-exceeded' for e in value['errors']):
            raise ValueError(value['errors'])
        time.sleep(60)


def projects():
    approved = read(ROOT / 'tools/artblocks/reviews/approved.json')['collections']
    provenance = {p['identity']: p for p in read(ARCHIVE / 'provenance.json')['collections']}
    return [dict(provenance[a['identity']], identity=a['identity']) for a in approved]


def validate_tokens(project, tokens, cutoff, reviewed):
    chain, address, pid = project['identity'].split(':')
    if len(tokens) != cutoff:
        raise ValueError(f'Incomplete tokens {project["name"]}: {len(tokens)}/{cutoff}')
    for index, token in enumerate(tokens):
        token_id = str(int(pid) * 1000000 + index)
        if token.get('token_id') != token_id or token.get('id') != f'{address}-{token_id}' or token.get('chain_id') != int(chain) or token.get('contract_address', '').lower() != address or token.get('project_id') != f'{address}-{pid}' or token.get('invocation') != index:
            raise ValueError(f'Token identity/order conflict {project["identity"]}/{index}')
        value = token.get('hash', '')
        if len(value) != 66 or not value.startswith('0x') or any(c not in '0123456789abcdefABCDEF' for c in value[2:]):
            raise ValueError(f'Invalid hash {project["identity"]}/{index}')
        old = reviewed.get(token_id)
        if old and old['hash'].lower() != value.lower():
            raise ValueError(f'Reviewed hash changed {project["identity"]}/{index}')
        if project['name'].strip().lower() == 'autorad':
            size = (token.get('image') or {}).get('metadata') or {}
            if not old and (not isinstance(size.get('width'), int) or not isinstance(size.get('height'), int) or min(size['width'], size['height']) <= 0):
                raise ValueError(f'Missing autoRAD reference geometry: {token_id}')
    if not set(reviewed).issubset({t['token_id'] for t in tokens}):
        raise ValueError(f'Reviewed tokens beyond cutoff: {project["name"]}')



def validate_parameter_record(job, token, record, reviewed=None):
    label = f'{job["identity"]}/{token["token_id"]}'
    if not isinstance(record, dict) or not isinstance(record.get('hash'), str) or record['hash'].lower() != token['hash'].lower():
        raise ValueError(f'Parameter hash conflict: {label}')
    parameters = record.get('parameters')
    if not isinstance(parameters, dict) or any(not isinstance(key, str) or not isinstance(value, str) for key, value in parameters.items()):
        raise ValueError(f'Invalid frozen parameter object: {label}')
    if reviewed is not None:
        if record.get('source') != 'reviewed-frozen-record' or parameters != reviewed['previewContractParameters']:
            raise ValueError(f'Reviewed parameter overwrite: {label}')
    else:
        chain, address, _ = job['identity'].split(':')
        if record.get('sourceScriptSHA256') != job['sourceScriptSHA256']:
            raise ValueError(f'Frozen parameter source fingerprint conflict: {label}')
        if record.get('dependency') != job['dependency']:
            raise ValueError(f'Frozen parameter dependency conflict: {label}')
        if record.get('sourceURL') != f'https://generator.artblocks.io/{chain}/{address}/{token["token_id"]}':
            raise ValueError(f'Frozen parameter source URL conflict: {label}')


def capture_project(project, cutoff, directory, offline):
    chain, address, pid = project['identity'].split(':')
    stem = f'{chain}-{address}-{pid}'
    destination = directory / 'tokens' / f'{stem}.json'
    reviewed = {t['id']: t for t in read(ARCHIVE / 'Tokens' / f'{project["collectionId"]}.json')['items']}
    if destination.exists():
        tokens = read(destination)
    else:
        tokens = []
        for offset in range(0, cutoff, PAGE_SIZE):
            page_path = directory / 'pages' / stem / f'{offset}.json'
            if page_path.exists():
                page = read(page_path)
            elif offline:
                raise ValueError(f'Missing captured token page {page_path}')
            else:
                page = graphql('''query PromotionTokens($project: String!, $chain: Int!, $address: String!, $cutoff: Int!, $offset: Int!) {
                  tokens_metadata(where: {project_id: {_eq: $project}, chain_id: {_eq: $chain}, contract_address: {_eq: $address}, invocation: {_lt: $cutoff}}, order_by: [{invocation: asc}, {id: asc}], limit: 500, offset: $offset) {
                    id chain_id contract_address project_id token_id invocation hash image { metadata }
                  }
                }''', {'project': f'{address}-{pid}', 'chain': int(chain), 'address': address, 'cutoff': cutoff, 'offset': offset})['tokens_metadata']
                if len(page) != min(PAGE_SIZE, cutoff - offset):
                    raise ValueError(f'Incomplete capture page: {stem}/{offset}: {len(page)}')
                save(page_path, page)
            tokens.extend(page)
        validate_tokens(project, tokens, cutoff, reviewed)
        save(destination, tokens)
    validate_tokens(project, tokens, cutoff, reviewed)
    script = read(ARCHIVE / 'Scripts' / f'{project["collectionId"]}.json')
    dependencies = script.get('externalAssetDependencies', [])
    contracts = [d for d in dependencies if d.get('dependency_type') == 'ONCHAIN' and d.get('bytecode_address')]
    if contracts:
        if len(contracts) != 1:
            raise ValueError(f'Unexpected contract dependencies: {stem}')
        job = {'identity': project['identity'], 'dependency': contracts[0], 'sourceScriptSHA256': hashlib.sha256(script['value'].encode()).hexdigest()}
        parameters_path = directory / 'parameters' / f'{stem}.json'
        parameters = read(parameters_path) if parameters_path.exists() else {}
        for token in tokens:
            token_id = token['token_id']
            old = reviewed.get(token_id, {})
            if old.get('previewContractParameters') is not None:
                if token_id in parameters:
                    validate_parameter_record(job, token, parameters[token_id], old)
                parameters[token_id] = {'hash': old['hash'], 'parameters': old['previewContractParameters'], 'source': 'reviewed-frozen-record'}
            elif token_id not in parameters:
                if offline:
                    raise ValueError(f'Missing frozen parameters: {stem}/{token_id}')
                url = f'https://generator.artblocks.io/{chain}/{address}/{token_id}'
                html = request(url)
                values = parse_generator(html, job, {'id': token_id, 'hash': token['hash']}, url)
                parameters[token_id] = {'hash': token['hash'], 'parameters': values, 'sourceURL': url, 'fetchedAt': now(), 'sourceScriptSHA256': job['sourceScriptSHA256'], 'dependency': job['dependency']}
                validate_parameter_record(job, token, parameters[token_id])
                save(parameters_path, parameters)
            validate_parameter_record(job, token, parameters[token_id], old if old.get('previewContractParameters') is not None else None)
        save(parameters_path, parameters)
    return project['name'], len(tokens)


def required_capture_files(selected):
    required = {'cutoff.json'}
    for project in selected:
        stem = project['identity'].replace(':', '-')
        required.add(f'tokens/{stem}.json')
        script = read(ARCHIVE / 'Scripts' / f'{project["collectionId"]}.json')
        if any(asset.get('dependency_type') == 'ONCHAIN' for asset in script.get('externalAssetDependencies', [])):
            required.add(f'parameters/{stem}.json')
    return required


def validate_capture_checksums(directory, completion, required):
    files = completion.get('files')
    if not isinstance(files, dict) or set(files) != required:
        raise ValueError('Frozen capture checksum membership mismatch')
    for relative, digest in files.items():
        if hashlib.sha256((directory / relative).read_bytes()).hexdigest() != digest:
            raise ValueError(f'Frozen capture checksum mismatch: {relative}')


def main():
    parser = argparse.ArgumentParser(description='Freeze complete minted-token data without changing artist scripts or previously reviewed parameters.')
    parser.add_argument('--capture', type=pathlib.Path, default=CAPTURE)
    parser.add_argument('--offline', action='store_true')
    args = parser.parse_args()
    selected = projects()
    required_files = required_capture_files(selected)
    completion_path = args.capture / 'complete.json'
    if completion_path.exists():
        validate_capture_checksums(args.capture, read(completion_path), required_files)
    cutoff_path = args.capture / 'cutoff.json'
    if cutoff_path.exists():
        cutoff = read(cutoff_path)
    else:
        if args.offline:
            raise ValueError('Missing frozen capture cutoff')
        captured_at = now()
        rows = graphql('''query PromotionCutoff($ids: [String!]!) {
          projects_metadata(where: {id: {_in: $ids}}, limit: 1000) { id chain_id contract_address project_id name artist_name invocations }
        }''', {'ids': [p['apiProjectId'] for p in selected]})['projects_metadata']
        lookup = {f'{r["chain_id"]}:{r["contract_address"].lower()}:{r["project_id"]}': r for r in rows}
        cutoffs = {}
        for project in selected:
            row = lookup.get(project['identity'])
            if not row or not isinstance(row['invocations'], int) or row['invocations'] < project['tokenCount'] or row['name'] != project['name']:
                raise ValueError(f'Invalid project cutoff: {project["identity"]}')
            cutoffs[project['identity']] = row
        cutoff = {'version': 1, 'capturedAt': captured_at, 'endpoint': API, 'collections': cutoffs}
        save(cutoff_path, cutoff)
    if set(cutoff['collections']) != {p['identity'] for p in selected}:
        raise ValueError('Cutoff approval identities conflict')
    print(f'Frozen {len(selected)} collections / {sum(p["invocations"] for p in cutoff["collections"].values())} minted tokens at {cutoff["capturedAt"]}', flush=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
        futures = [executor.submit(capture_project, p, cutoff['collections'][p['identity']]['invocations'], args.capture, args.offline) for p in selected]
        total = 0
        for index, future in enumerate(concurrent.futures.as_completed(futures), 1):
            name, count = future.result()
            total += count
            print(f'{index}/{len(selected)} validated: {name} ({count}); {total} tokens', flush=True)
    ordered_files = ['cutoff.json'] + sorted(relative for relative in required_files if relative.startswith('tokens/')) + sorted(relative for relative in required_files if relative.startswith('parameters/'))
    frozen_files = [args.capture / relative for relative in ordered_files]
    hashes = {str(file.relative_to(args.capture)): hashlib.sha256(file.read_bytes()).hexdigest() for file in frozen_files}
    save(completion_path, {'version': 1, 'capturedAt': cutoff['capturedAt'], 'collections': len(selected), 'tokens': total, 'files': hashes})


if __name__ == '__main__':
    main()
