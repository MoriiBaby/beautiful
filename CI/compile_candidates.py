#!/usr/bin/env python3
"""Apple ObjC++ and Swift candidate object compilation, no main activation/link/package."""
import json,os,platform,shlex,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'artifacts';OBJECTS=OUT/'candidate-objects';OBJECTS.mkdir(parents=True,exist_ok=True)
assert platform.system()=='Darwin','Apple SDK compiler required'
def run(args):
    print('$ '+shlex.join(map(str,args)),flush=True)
    subprocess.run(list(map(str,args)),cwd=ROOT,check=True)
def xcrun(*args):
    return subprocess.check_output(['xcrun','--sdk','iphoneos',*args],text=True).strip()
sdk=xcrun('--show-sdk-path');clang=xcrun('--find','clang++');swift=xcrun('--find','swiftc')
source_names=subprocess.check_output(['rg','--files','Sources/Main','-g','*.mm'],cwd=ROOT,text=True).splitlines()
record={'scope':'Main candidates OBJECTS ONLY; main unavailable, not linked or loaded',
        'architectures':['arm64','arm64e'],'sdk':sdk,'commands':[]}
for arch in record['architectures']:
    directory=OBJECTS/arch;directory.mkdir(exist_ok=True)
    for name in sorted(source_names):
        obj=directory/(name.replace('/','__')+'.o')
        args=[clang,'-target',arch+'-apple-ios15.0','-isysroot',sdk,'-std=c++17',
              '-fobjc-arc','-fblocks','-ISources/Shared','-Werror=return-type',
              '-c',name,'-o',obj]
        run(args);record['commands'].append(list(map(str,args)))
    args=[swift,'-target',arch+'-apple-ios15.0','-sdk',sdk,'-swift-version','5',
          '-parse-as-library','-emit-object','-module-name','SthenoRebuildCandidate',
          '-import-objc-header','Tools/SthenoRebuildMain-Bridging-Header.h',
          'Sources/Main/SRFloatingCoordinator.swift','-o',directory/'SRFloatingCoordinator.o']
    run(args);record['commands'].append(list(map(str,args)))
(OUT/'candidate-compile.json').write_text(json.dumps(record,indent=2))
