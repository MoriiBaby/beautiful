#!/usr/bin/env python3
"""Local iOS evidence targets only. Never signs, installs, or packages a DEB."""
import argparse, datetime, hashlib, json, os, platform, shlex, shutil, subprocess, sys
from pathlib import Path
import deps, macho
ROOT = deps.ROOT
ARCHS = ('arm64', 'arm64e')

def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + '\n')

def check_tools(link=False):
    names = ['clang-19', 'rg', 'git'] + (['ld64.lld', 'llvm-lipo'] if link else [])
    missing = [x for x in names if not shutil.which(x)]
    if missing: raise RuntimeError('Missing local tools: ' + ', '.join(missing) + '; install Alpine clang19/lld/llvm and ripgrep explicitly.')

def full_blockers():
    result = []
    if not shutil.which('xcrun'): result.append('xcrun/iOS Swift toolchain missing: full main needs macOS Xcode + SDK, not Linux swiftc.')
    if not shutil.which('swiftc'): result.append('swiftc missing; ObjC module success is NOT Swift/Orion success.')
    theos = os.environ.get('THEOS')
    if not theos or not (Path(theos) / 'makefiles/common.mk').is_file():
        result.append('Usable RootHide Theos missing: provision pinned official RootHide Theos/submodules on Mac and set THEOS.')
    else:
        if not (Path(theos) / 'vendor/mod/roothide/instance/library.mk').is_file(): result.append('THEOS is missing official RootHide scheme.')
        if not (Path(theos) / 'vendor/orion/Package.swift').is_file(): result.append('Theos Orion submodule is incomplete.')
    gate = ROOT / 'Tools/MAIN_READINESS.json'
    if not gate.is_file(): result.append('Main scene/entitlement closure review is missing.')
    else:
        state = json.loads(gate.read_text())
        for key in ('main_scene_hosting_implemented', 'main_scene_hosting_verified', 'entitlements_verified', 'licensing_preserved', 'full_package_reviewed'):
            if state.get(key) is not True: result.append('Main gate not satisfied: ' + key)
    main_dir = ROOT / 'Sources/Main'
    if not main_dir.is_dir() or not any(p.suffix == '.swift' for p in deps.files(main_dir)):
        result.append('Main Swift sources are not present.')
    scene_header = main_dir / 'SceneBridge/SRSceneHost.h'
    enabled = subprocess.run(['rg', '-q', r'^\s*#\s*define\s+SR_SCENE_HOSTING_IMPLEMENTED\s+1\s*$', str(scene_header)], capture_output=True)
    if enabled.returncode != 0: result.append('SR_SCENE_HOSTING_IMPLEMENTED is not 1; scene hosting is not restored.')
    return result

def preflight(full=False):
    result = {'scope': 'full-main' if full else 'small-objc-only', 'architecture_policy': list(ARCHS),
              'device_load': 'NOT TESTED', 'device_function': 'NOT TESTED', 'signing': 'NOT PERFORMED',
              'packaging': 'BLOCKED; no DEB/install target is authorized', 'full_main_blockers': full_blockers()}
    try:
        check_tools(); sdk = deps.verify()
        result['small_objc_sdk_compile'] = 'READY (not yet a compile result)'; result['sdk'] = str(sdk)
        result['sdk_metadata_version'] = deps.load()['sdk']['metadata_version']
        result['clang'] = deps.run(['clang-19', '--version']).splitlines()[0]
        result['linker_available'] = bool(shutil.which('ld64.lld'))
    except (RuntimeError, OSError, subprocess.SubprocessError) as e:
        result['small_objc_sdk_compile'] = 'BLOCKED'; result['local_error'] = str(e)
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 2 if 'local_error' in result or (full and result['full_main_blockers']) else 0

def sources(scope):
    directories = [ROOT / 'Sources/Shared']
    directories += [ROOT / ('Sources/' + x) for x in (['Camera', 'Keyboard'] if scope == 'small' else ['Main/SceneBridge', 'Main'])]
    selected = {}; inputs = {}
    for directory in directories:
        if not directory.is_dir(): raise RuntimeError('Source directory not ready: ' + str(directory))
        candidates = deps.files(directory)
        if directory == ROOT / 'Sources/Main': candidates = [p for p in candidates if p.parent == directory]
        compiled = [p for p in candidates if p.suffix in ('.mm', '.m', '.c', '.cc', '.cpp')]
        if not compiled: raise RuntimeError('No real source implementation in ' + str(directory))
        selected[directory.name] = compiled
        for p in candidates:
            if p.suffix in ('.mm', '.m', '.c', '.cc', '.cpp', '.h', '.hpp'): inputs[str(p.relative_to(ROOT))] = deps.sha(p)
    for rel in ('Dependencies.lock.json', 'Makefile', 'control', 'Tools/build.py', 'Tools/deps.py', 'Tools/macho.py', 'Tools/guard.py'):
        inputs[rel] = deps.sha(ROOT / rel)
    return selected, inputs

def logrun(cmd, log, record):
    cmd = [str(x) for x in cmd]
    log.parent.mkdir(parents=True, exist_ok=True)
    with open(log, 'w') as out:
        out.write('$ ' + shlex.join(cmd) + '\n'); out.flush()
        p = subprocess.run(cmd, cwd=ROOT, stdout=out, stderr=subprocess.STDOUT)
        out.write('\nexit_code=' + str(p.returncode) + '\n')
    record['commands'].append({'argv': cmd, 'exit_code': p.returncode, 'log': str(log.relative_to(ROOT))})
    print(('PASS ' if p.returncode == 0 else 'FAIL ') + str(log.relative_to(ROOT)), flush=True)
    if p.returncode: raise RuntimeError('Compiler/linker failed; preserved diagnostics: ' + str(log))

def compile_source(path, arch, sdk, out, log, record):
    cmd = ['clang-19', '--no-default-config', '-target', arch + '-apple-ios15.0', '-isysroot', sdk,
           '-I', deps.CACHE / 'include', '-I', ROOT / 'Sources/Shared', '-fblocks', '-fPIC',
           '-DTHEOS_PACKAGE_SCHEME_ROOTHIDE=1', '-Werror=return-type', '-Werror=implicit-function-declaration',
           '-MD', '-MF', str(out) + '.d']
    if path.suffix in ('.m', '.mm'): cmd += ['-fobjc-arc']
    if path.suffix in ('.mm', '.cc', '.cpp'):
        cmd += ['-std=c++17', '-stdlib=libc++', '-nostdinc++', '-isystem', sdk / 'usr/include/c++/v1']
    else: cmd += ['-std=c11'] if path.suffix == '.c' else []
    cmd += ['-c', path, '-o', out]
    logrun(cmd, log, record)
    metadata = macho.validate(out, [arch], 'object')
    record['artifacts'].append({'path': str(out.relative_to(ROOT)), 'sha256': deps.sha(out), 'macho': metadata,
                                'state': 'COMPILED iOS object; not linked, signed, loaded or install-ready'})
    save(Path(str(out) + '.macho.json'), metadata)
    if shutil.which('llvm-readobj'): logrun(['llvm-readobj', '--file-headers', '--macho-version-min', out], Path(str(log) + '.macho'), record)

def build(do_link=False, scope='small'):
    check_tools(do_link); sdk = deps.verify(); selected, inputs = sources(scope)
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%S.%fZ')
    label = ('link' if do_link else 'compile') + '-' + scope + '-' + stamp
    outdir = ROOT / 'Tools/Build' / label; logdir = ROOT / 'Tools/Logs' / label
    outdir.mkdir(parents=True); logdir.mkdir(parents=True)
    record = dict(scope=scope, status='RUNNING', commands=[], artifacts=[], inputs=inputs,
                  architectures=list(ARCHS), sdk=str(sdk), signed=False, loaded=False,
                  install_ready=False, full_main='BLOCKED', host=platform.platform())
    manifest = outdir / 'build.json'; failures = []; objects = {}
    try:
        for arch in ARCHS:
            (outdir / arch).mkdir()
            for group, paths in selected.items():
                objects[arch, group] = []
                for source in paths:
                    name = str(source.relative_to(ROOT)).replace('/', '__')
                    obj = outdir / arch / (name + '.o')
                    try:
                        compile_source(source, arch, sdk, obj, logdir / (arch + '-' + name + '.log'), record)
                        objects[arch, group].append(obj)
                    except (RuntimeError, ValueError) as e: failures.append(str(e))
        if failures: raise RuntimeError('\n'.join(failures))
        record['compile_status'] = 'PASS_BOTH_ARCHITECTURES'
        if do_link:
            if scope != 'small': raise RuntimeError('Scene bridge/Main link is deliberately unsupported while host gate is incomplete.')
            verified = {}
            for arch in ARCHS:
                for module in ('Camera', 'Keyboard'):
                    name = 'SthenoRebuild' + module
                    output = outdir / arch / (name + '.dylib')
                    install = '@loader_path/.jbroot/Library/MobileSubstrate/DynamicLibraries/' + name + '.dylib'
                    cmd = ['ld64.lld', '-dylib', '-arch', arch, '-arch_errors_fatal', '-platform_version', 'ios', '15.0',
                           deps.load()['sdk']['metadata_version'], '-syslibroot', sdk, '-install_name', install,
                           '-no_adhoc_codesign', '-undefined', 'error', '-o', output,
                           *objects[arch, module], *objects[arch, 'Shared'], '-L', deps.CACHE / 'lib',
                           '-lroothide', '-lsubstrate', '-framework', 'Foundation', '-framework', 'CoreFoundation',
                           '-lobjc', '-lSystem', '-lc++']
                    if module == 'Keyboard': cmd += ['-framework', 'UIKit', '-framework', 'CoreGraphics']
                    log = logdir / (arch + '-' + name + '-link.log')
                    try:
                        logrun(cmd, log, record)
                        if shutil.which('llvm-readobj'):
                            logrun(['llvm-readobj', '--file-headers', '--macho-version-min', '--needed-libs', output], Path(str(log) + '.raw-macho'), record)
                        metadata = macho.validate(output, [arch], 'dylib', install)
                        save(Path(str(output) + '.macho.json'), metadata)
                        record['artifacts'].append(dict(path=str(output.relative_to(ROOT)), sha256=deps.sha(output), macho=metadata,
                            state='UNSIGNED linked evidence ONLY; NOT loaded, NOT install-ready'))
                        verified[arch, module] = output
                        if shutil.which('llvm-objdump'):
                            logrun(['llvm-objdump', '--macho', '--private-headers', '--dylibs-used', output], Path(str(log) + '.macho'), record)
                    except (RuntimeError, ValueError) as e:
                        failures.append(str(e))
                        if output.exists():
                            rejected = Path(str(output) + '.REJECTED')
                            metadata = macho.parse(output.read_bytes())
                            output.rename(rejected)
                            save(Path(str(rejected) + '.macho.json'), metadata)
                            record.setdefault('rejected_artifacts', []).append(dict(
                                path=str(rejected.relative_to(ROOT)), sha256=deps.sha(rejected), expected_architecture=arch,
                                macho=metadata, reason=str(e), state='REJECTED; not a usable target dylib; no header rewriting'))
            for module in ('Camera', 'Keyboard'):
                if all((arch, module) in verified for arch in ARCHS):
                    output = outdir / ('SthenoRebuild' + module + '.dylib')
                    try:
                        logrun(['llvm-lipo', '-create', *[verified[a, module] for a in ARCHS], '-output', output], logdir / (module + '-lipo.log'), record)
                        install = '@loader_path/.jbroot/Library/MobileSubstrate/DynamicLibraries/SthenoRebuild' + module + '.dylib'
                        metadata = macho.validate(output, list(ARCHS), 'dylib', install)
                        save(Path(str(output) + '.macho.json'), metadata)
                        record['artifacts'].append(dict(path=str(output.relative_to(ROOT)), sha256=deps.sha(output), macho=metadata,
                            state='UNSIGNED universal evidence ONLY; NOT loaded, NOT install-ready'))
                    except (RuntimeError, ValueError) as e: failures.append(str(e))
            if failures: raise RuntimeError('\n'.join(failures))
        _, after = sources(scope)
        if after != inputs: raise RuntimeError('Source/dependency lock changed during build; evidence is stale. Rerun on stable sources.')
        record['status'] = 'IOS_LINKED_UNSIGNED_NOT_LOADED' if do_link else 'IOS_OBJECTS_COMPILED_NOT_LINKED'
        if scope == 'scene': record['main_feature_status'] = 'BLOCKED: SR_SCENE_HOSTING_IMPLEMENTED=0; compile does not restore hosting.'
    except (RuntimeError, OSError, ValueError, subprocess.SubprocessError) as e:
        record['status'] = 'FAILED'; record['error'] = str(e)
    try:
        _, after = sources(scope)
        record['input_snapshot_still_current'] = after == inputs
        if after != inputs:
            record['status'] = 'FAILED'
            record['error'] = record.get('error', '') + '\nInputs changed during build; rerun required.'
    except (RuntimeError, OSError) as e:
        record['input_snapshot_still_current'] = False
        record['status'] = 'FAILED'; record['error'] = str(e)
    record['link_status'] = ('FAILED_TARGET_VALIDATION_OR_LINK' if record['status'] == 'FAILED' else 'VERIFIED_BOTH_ARCHITECTURES') if do_link else 'NOT_REQUESTED'
    save(manifest, record)
    pointer = dict(manifest=str(manifest.relative_to(ROOT)), status=record['status'])
    save(ROOT / ('Tools/Build/latest-' + scope + '.json'), pointer)
    save(ROOT / ('Tools/Build/latest-' + ('link-' if do_link else 'compile-') + scope + '.json'), pointer)
    print('RESULT', record['status'], str(manifest.relative_to(ROOT)), flush=True)
    if record['status'] == 'FAILED': print(record['error'], file=sys.stderr); return 2
    return 0

def main_guard():
    blockers = full_blockers()
    if blockers:
        print('BLOCKED: full main is incomplete; no complete-restore package may be built.\n' + '\n'.join(blockers), file=sys.stderr)
        return 2
    return 0

def main():
    ap = argparse.ArgumentParser(); ap.add_argument('action', choices=['preflight', 'local-preflight', 'compile', 'link', 'scene-compile', 'main-guard', 'package-guard'])
    a = ap.parse_args()
    try:
        if a.action == 'preflight': return preflight(True)
        if a.action == 'local-preflight': return preflight(False)
        if a.action == 'main-guard': return main_guard()
        if a.action == 'package-guard':
            print('BLOCKED: packaging/staging/installation are disabled. Main scene/entitlement closure and separate authorization are required.', file=sys.stderr); return 2
        return build(a.action == 'link', 'scene' if a.action == 'scene-compile' else 'small')
    except (RuntimeError, OSError, ValueError, subprocess.SubprocessError) as e:
        print('BLOCKED:', e, file=sys.stderr); return 2

if __name__ == '__main__': sys.exit(main())
