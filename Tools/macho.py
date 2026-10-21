#!/usr/bin/env python3
"""Read Mach-O headers/load commands, never execute or load a produced image."""
import argparse, json, struct, sys
from pathlib import Path

def version(v): return '%d.%d.%d' % ((v >> 16) & 65535, (v >> 8) & 255, v & 255)
def cstring(b, at): return b[at:].split(b'\0', 1)[0].decode('utf-8', 'strict')
def parse(data):
    magic = data[:4]
    if magic in (b'\xca\xfe\xba\xbe', b'\xca\xfe\xba\xbf'):
        n = struct.unpack_from('>I', data, 4)[0]; result = []; at = 8
        for _ in range(n):
            fmt = '>IIQQII' if magic[-1] == 191 else '>IIIII'
            fields = struct.unpack_from(fmt, data, at); at += struct.calcsize(fmt)
            cpu, sub, offset, size = fields[:4]
            child = parse(data[offset:offset + size]); assert len(child) == 1
            assert child[0]['cpu_type'] == cpu and child[0]['cpu_subtype_raw'] == sub
            result.extend(child)
        return result
    if magic != b'\xcf\xfa\xed\xfe': raise ValueError('Expected little-endian 64-bit Mach-O')
    _, cpu, sub, kind, count, cmdsize, flags, reserved = struct.unpack_from('<8I', data)
    arch = {0: 'arm64', 2: 'arm64e'}.get(sub & 0xFFFFFF, 'unknown') if cpu == 0x100000C else 'non-arm64'
    item = dict(cpu_type=cpu, cpu_subtype_raw=sub, architecture=arch,
                file_type=kind, flags=flags, dependencies=[], install_name=None,
                build_versions=[], code_signature=False)
    at = 32
    for _ in range(count):
        cmd, size = struct.unpack_from('<II', data, at)
        if size < 8 or at + size > len(data): raise ValueError('Invalid load command bounds')
        block = data[at:at + size]
        if cmd == 0x32:
            platform, minimum, sdk, tools = struct.unpack_from('<4I', block, 8)
            item['build_versions'].append(dict(platform=platform, minimum_os=version(minimum), sdk=version(sdk)))
        elif cmd == 0x25:
            minimum, sdk = struct.unpack_from('<2I', block, 8)
            item['build_versions'].append(dict(platform=2, minimum_os=version(minimum), sdk=version(sdk)))
        elif cmd in (0xC, 0xD, 0x80000018, 0x8000001F, 0x80000023, 0x20):
            name = cstring(block, struct.unpack_from('<I', block, 8)[0])
            if cmd == 0xD: item['install_name'] = name
            else: item['dependencies'].append(name)
        elif cmd == 0x1D:
            item['code_signature'] = bool(struct.unpack_from('<II', block, 8)[1])
        at += size
    if at != 32 + cmdsize: raise ValueError('Load command total mismatch')
    return [item]

def validate(path, archs, kind, install_name=None):
    items = parse(Path(path).read_bytes())
    if sorted(x['architecture'] for x in items) != sorted(archs):
        raise ValueError('Architecture/subtype mismatch (will NOT substitute arm64 for arm64e): ' + str(items))
    for item in items:
        if item['file_type'] != (1 if kind == 'object' else 6): raise ValueError('Unexpected Mach-O file type')
        if not item['build_versions'] or any(x['platform'] != 2 or x['minimum_os'] != '15.0.0' for x in item['build_versions']):
            raise ValueError('Not iOS device minimum OS 15.0: ' + str(item))
        if kind == 'dylib':
            if item['code_signature']: raise ValueError('Local evidence target must be unsigned')
            if item['install_name'] != install_name: raise ValueError('Unexpected dylib install name')
            required = {'@loader_path/.jbroot/usr/lib/libroothide.dylib', '/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate'}
            if not required.issubset(item['dependencies']): raise ValueError('Missing official RootHide/Substrate runtime dependency')
            if any('Stheno.dylib' in x for x in item['dependencies']): raise ValueError('Original dylib dependency forbidden')
            for dep in item['dependencies']:
                if dep not in required and not dep.startswith(('/usr/lib/', '/System/Library/Frameworks/')):
                    raise ValueError('Unreviewed runtime dependency: ' + dep)
    return items

if __name__ == '__main__':
    ap=argparse.ArgumentParser(); ap.add_argument('file'); ap.add_argument('--arch', action='append', required=True)
    ap.add_argument('--kind', choices=['object', 'dylib'], required=True); ap.add_argument('--install-name'); a=ap.parse_args()
    try: print(json.dumps(validate(a.file, a.arch, a.kind, a.install_name), indent=2))
    except (OSError, ValueError, AssertionError, struct.error) as e:
        print('FAIL:', e, file=sys.stderr); sys.exit(2)
