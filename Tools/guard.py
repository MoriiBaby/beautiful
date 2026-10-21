#!/usr/bin/env python3
"""Fast source/config safety checks. This is NOT an SDK compile or device test."""
import json, plistlib, re, sys
from pathlib import Path
import deps
ROOT = deps.ROOT

def require(condition, message):
    if not condition: raise RuntimeError(message)

def check():
    fields = dict(line.split(':', 1) for line in (ROOT / 'control').read_text().splitlines() if ':' in line)
    fields = {k: v.strip() for k, v in fields.items()}
    require(fields.get('Package') == 'com.local.stheno.reconstruction', 'Wrong package ID')
    require(fields.get('Version') == '0.1.0~dev1', 'Wrong dev version')
    require(fields.get('Architecture') == 'iphoneos-arm64e', 'RootHide package architecture changed')
    require('com.nx.stheno' in fields.get('Conflicts', '').split(', '), 'Original package conflict guard missing')
    require('Replaces' not in fields and 'Provides' not in fields, 'No replacement/impersonation metadata allowed')
    require('roothide' in fields.get('Depends', '') and 'dev.theos.orion' in fields.get('Depends', ''), 'Explicit runtime dependencies missing')
    expected = {'Camera': {'Executables': ['mediaserverd']}, 'Keyboard': {'Bundles': ['com.apple.UIKit']},
                'Main': {'Bundles': ['com.apple.springboard']}}
    for module, filter_value in expected.items():
        path = ROOT / ('Filters/SthenoRebuild' + module + '.plist')
        require(plistlib.loads(path.read_bytes()) == {'Filter': filter_value}, 'Unexpected injection filter: ' + module)
    makefile = (ROOT / 'Makefile').read_text()
    require('.DEFAULT_GOAL := all' in makefile and 'all: full' in makefile, 'Default full guard is not wired')
    require('Tools/build.py main-guard' in makefile, 'Full main guard missing')
    require('Packaging/staging/device operations are disabled' in makefile, 'Package/install hard stop missing')
    require(not re.search(r'after-install|killall|sbreload|launchctl|INSTALL_TARGET_PROCESSES', makefile, re.I), 'Automatic device side effect in Makefile')
    names = re.search(r'^TWEAK_NAME\s*:?=\s*(.*)$', makefile, re.M)
    require(names and names.group(1).split() == ['SthenoRebuildCamera', 'SthenoRebuildKeyboard', 'SthenoRebuildMain'], 'Dylib names must stay independent')
    for module in expected:
        require('SthenoRebuild' + module + '_INSTALL := 0' in makefile, 'Unreviewed Theos staging enabled')
    lock = deps.load()
    require(lock['target']['architectures'] == ['arm64', 'arm64e'], 'Do not drop/replace chosen architectures')
    require(lock['target']['minimum_os'] == '15.0', 'Unexpected target minimum OS')
    require(re.fullmatch('[0-9a-f]{40}', lock['sdk']['commit']), 'SDK must pin an immutable commit')
    require(re.fullmatch('[0-9a-f]{64}', lock['sdk']['materialized_manifest_sha256']), 'SDK full content SHA256 missing')
    require(not Path(lock['cache_default']).is_relative_to(ROOT), 'Public SDK must be external to the source deliverable')
    for entry in lock['files']:
        require(re.fullmatch('[0-9a-f]{64}', entry['sha256']), 'Dependency SHA256 missing')
        require(entry['url'].startswith('https://raw.githubusercontent.com/') and entry['commit'] in entry['url'], 'Unpinned dependency URL')
    workflows = ROOT / '.github/workflows'
    if workflows.is_dir():
        workflow_files = deps.files(workflows)
        require([p.name for p in workflow_files] == ['macos-small-modules.yml'],
                'Only the reviewed macOS small-module workflow is allowed')
        workflow = workflow_files[0].read_text()
        require('runs-on: macos-26' in workflow and 'CI/build_small_modules.sh' in workflow,
                'Cloud workflow must use pinned macOS and small-module target')
        build_script = (ROOT / 'CI/build_small_modules.sh').read_text()
        require('gmake -f CI/SmallModules.mk all' in build_script,
                'Cloud build script must call the reviewed small-module Makefile')
        require('actions/checkout@11d5960a326750d5838078e36cf38b85af677262' in workflow,
                'Checkout action must be pinned')
        require('actions/upload-artifact@ea165f8d65b6e75b540449e92b4886f43607fa02' in workflow,
                'Artifact action must be pinned')
        require(not re.search(r'(?i)(install_app|dpkg|sbreload|killall|frida|ssh|STATUSBARSPEED|package|stage|install target)', workflow),
                'Cloud workflow contains a device/package/credential operation')
    for path in deps.files(ROOT):
        require(path.suffix != '.deb', 'No DEB artifacts allowed in this incomplete source tree')
    return {'source_and_package_configuration': 'PASS', 'ios_compile': 'NOT RUN BY THIS CHECK',
            'device_load': 'NOT TESTED', 'full_restore_package': 'BLOCKED'}

if __name__ == '__main__':
    try: print(json.dumps(check(), indent=2))
    except (RuntimeError, OSError, ValueError, KeyError) as e:
        print('FAIL:', e, file=sys.stderr); sys.exit(2)
