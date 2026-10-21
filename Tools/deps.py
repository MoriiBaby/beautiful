#!/usr/bin/env python3
"""Pinned public inputs only. No installer, device, signing, or code upload."""
import argparse, hashlib, json, os, posixpath, shutil, subprocess, sys, urllib.request
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
CACHE = Path(os.environ.get('STHENO_CACHE', '/var/minis/workspace/stheno-toolchain')).resolve()

def sha(path):
    h = hashlib.sha256()
    with open(path, 'rb') as f:
        for b in iter(lambda: f.read(1024 * 1024), b''): h.update(b)
    return h.hexdigest()

def run(args):
    return subprocess.check_output([str(x) for x in args], stderr=subprocess.PIPE).decode().strip()

def files(directory):
    p = subprocess.run(['rg', '--files', '-uuu', '-0', str(directory)], capture_output=True)
    if p.returncode not in (0, 1): raise RuntimeError(p.stderr.decode())
    return sorted(Path(os.fsdecode(x)) for x in p.stdout.split(b'\0') if x)

def snapshot(sdk):
    rows = [{'path': str(p.relative_to(sdk)), 'sha256': sha(p)} for p in files(sdk)]
    data = (json.dumps(rows, sort_keys=True, separators=(',', ':')) + '\n').encode()
    return rows, hashlib.sha256(data).hexdigest(), data

def materialize(repo, subdir):
    """iOS shared FS forbids symlinks; copy ONLY their original Git targets."""
    entries = subprocess.check_output(['git', '-C', str(repo), 'ls-tree', '-r', '-z', 'HEAD', subdir])
    links = {}
    for item in entries.split(b'\0'):
        if not item: continue
        meta, name = item.split(b'\t', 1)
        mode, kind, oid = meta.decode().split()
        if mode == '120000':
            name = name.decode()
            value = subprocess.check_output(['git', '-C', str(repo), 'cat-file', 'blob', oid]).decode()
            links[name] = value
    def resolve(name):
        for _ in range(100):
            parts = name.split('/')
            for i in range(1, len(parts) + 1):
                prefix = '/'.join(parts[:i])
                if prefix in links:
                    target = links[prefix]
                    if target.startswith('/'): raise RuntimeError('Absolute SDK symlink: ' + prefix)
                    name = posixpath.normpath(posixpath.join(posixpath.dirname(prefix), target, *parts[i:]))
                    if not name.startswith(subdir + '/'): raise RuntimeError('SDK link escapes SDK: ' + name)
                    break
            else: return name
        raise RuntimeError('SDK symlink cycle')
    for name in sorted(links, key=lambda x: x.count('/'), reverse=True):
        dst, src = repo / name, repo / resolve(name)
        if not src.exists(): raise RuntimeError('Official SDK dangling link: ' + name)
        if dst.is_symlink():
            if os.readlink(dst) != links[name]: raise RuntimeError('Modified SDK symlink: ' + name)
            dst.unlink()
        elif dst.is_file():
            if dst.read_bytes() == links[name].encode(): dst.unlink()
            elif src.is_file() and sha(dst) == sha(src): continue
            else: raise RuntimeError('Refusing to overwrite modified SDK link: ' + name)
        if src.is_dir():
            dst.mkdir(parents=True, exist_ok=True)
            for child in files(src):
                out = dst / child.relative_to(src)
                if out.exists() and sha(out) != sha(child): raise RuntimeError('Modified SDK alias: ' + str(out))
                out.parent.mkdir(parents=True, exist_ok=True)
                if not out.exists(): out.write_bytes(child.read_bytes())
        elif not dst.exists(): dst.write_bytes(src.read_bytes())
    return len(links)

def load():
    return json.loads((ROOT / 'Dependencies.lock.json').read_text())

def verify(lock=None):
    lock = lock or load()
    sdk = lock['sdk']; repo = CACHE / sdk['repository_cache']; path = repo / sdk['subdir']
    if not path.exists(): raise RuntimeError('SDK missing. Run `make deps-fetch` (public downloads), then retry.')
    if run(['git', '-C', repo, 'rev-parse', 'HEAD']) != sdk['commit']:
        raise RuntimeError('SDK commit differs from lock; use a fresh STHENO_CACHE and `make deps-fetch`.')
    if run(['git', '-C', repo, 'rev-parse', 'HEAD:' + sdk['subdir']]) != sdk['git_tree']:
        raise RuntimeError('SDK Git tree differs from lock')
    rows, digest, data = snapshot(path)
    if digest != sdk['materialized_manifest_sha256']:
        raise RuntimeError('SDK content SHA256 manifest differs (no automatic patching): ' + digest)
    for entry in lock['files']:
        p = CACHE / entry['path']
        if not p.is_file() or sha(p) != entry['sha256']:
            raise RuntimeError('Missing/modified public dependency ' + entry['path'] + '; run `make deps-fetch`.')
    return path

def fetch():
    lock = load(); sdk = lock['sdk']; repo = CACHE / sdk['repository_cache']
    CACHE.mkdir(parents=True, exist_ok=True)
    if not (repo / '.git').exists():
        repo.mkdir(parents=True, exist_ok=True)
        for args in [['init'], ['config', 'core.hooksPath', '/dev/null'],
                     ['remote', 'add', 'origin', sdk['url']],
                     ['config', 'remote.origin.promisor', 'true'],
                     ['config', 'remote.origin.partialclonefilter', 'blob:none'],
                     ['fetch', '--depth=1', '--filter=blob:none', 'origin', sdk['commit']],
                     ['sparse-checkout', 'init', '--cone'],
                     ['sparse-checkout', 'set', sdk['subdir']], ['checkout', '--detach', 'FETCH_HEAD']]:
            subprocess.run(['git', '-C', str(repo), *args], check=True)
    if run(['git', '-C', repo, 'rev-parse', 'HEAD']) != sdk['commit']:
        raise RuntimeError('Existing SDK cache is not the pinned commit; use a fresh STHENO_CACHE.')
    count = materialize(repo, sdk['subdir'])
    print('SDK symlink targets preserved/materialized:', count)
    for entry in lock['files']:
        path = CACHE / entry['path']
        if path.exists():
            if sha(path) != entry['sha256']: raise RuntimeError('Modified dependency; refusing overwrite: ' + str(path))
            continue
        request = urllib.request.Request(entry['url'], headers={'User-Agent': 'Stheno-local-build/0.1'})
        with urllib.request.urlopen(request, timeout=120) as response: data = response.read()
        if hashlib.sha256(data).hexdigest() != entry['sha256']: raise RuntimeError('Downloaded SHA mismatch: ' + entry['url'])
        path.parent.mkdir(parents=True, exist_ok=True); path.write_bytes(data)
    verify(lock)
    print('PASS: pinned real SDK/header/stub content verified; no build/deployment implied.')

if __name__ == '__main__':
    ap = argparse.ArgumentParser(); ap.add_argument('action', choices=['fetch', 'verify']); args = ap.parse_args()
    try:
        if args.action == 'fetch': fetch()
        else: print('PASS:', verify())
    except (RuntimeError, OSError, subprocess.SubprocessError) as e:
        print('BLOCKED:', e, file=sys.stderr); sys.exit(2)
