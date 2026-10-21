#!/usr/bin/env bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"
export PATH="$(brew --prefix make)/libexec/gnubin:$PATH"
python3 - <<'PY'
import hashlib,json,os,subprocess
from pathlib import Path
root=Path('.')
for p in ['Makefile','CI/SmallModules.mk','Sources/Shared/SRRuntime.mm','Sources/Shared/SRPolicy.c','Sources/Camera/Camera.mm','Sources/Keyboard/Keyboard.mm']:
    assert (root/p).is_file(),p
print(json.dumps({'source_commit':subprocess.check_output(['git','rev-parse','HEAD'],text=True).strip(),'status':'source files present','files':6}))
PY
# run only project source/config guards; device/original audit evidence is intentionally absent on CI
python3 Tools/guard.py
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s Tests -p 'test_*.py' -v
export THEOS="${THEOS:?THEOS must point to pinned roothide/theos}"
export THEOS_PACKAGE_SCHEME=roothide
export ARCHS='arm64 arm64e'
# No package/stage/install target is called; TWEAK *_INSTALL=0 in CI/SmallModules.mk.
gmake -f CI/SmallModules.mk clean
gmake -f CI/SmallModules.mk all messages=yes COLOR=no
mkdir -p artifacts
rg --files -uuu .theos/obj -g '*.dylib' > artifacts/theos-products.txt
cat artifacts/theos-products.txt
[[ -s artifacts/theos-products.txt ]]
