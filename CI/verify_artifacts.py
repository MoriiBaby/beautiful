#!/usr/bin/env python3
"""Verify actual Apple/Theos products; never relabel headers or package/install."""
import hashlib,json,os,shutil,struct,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'Tools'))
import macho
OUT=ROOT/'artifacts';OUT.mkdir(exist_ok=True)
paths=subprocess.check_output(['rg','--files','-uuu','.theos/obj','-g','*.dylib'],cwd=ROOT,text=True).splitlines()
record={'commit':subprocess.check_output(['git','rev-parse','HEAD'],cwd=ROOT,text=True).strip(),
        'scope':'Two reconstructed small modules only; main hosting not restored; no device test',
        'main_enabled':False,'device_loaded':False,'package_created':False,'products':[]}
for module in ('Camera','Keyboard'):
    name='SthenoRebuild'+module+'.dylib'
    matches=[]
    for rel in paths:
        p=ROOT/rel
        if p.name!=name:continue
        info=macho.parse(p.read_bytes())
        if len(info)==2:matches.append((p,info))
    assert len(matches)==1,(name,'expected exactly one universal dylib',len(matches))
    path,info=matches[0]
    assert sorted(x['architecture'] for x in info)==['arm64','arm64e'],info
    for s in info:
        assert s['file_type']==6,'not MH_DYLIB'
        assert s['install_name']=='@loader_path/.jbroot/Library/MobileSubstrate/DynamicLibraries/'+name,s
        assert s['build_versions'] and all(v['platform']==2 and v['minimum_os']=='15.0.0' for v in s['build_versions']),s
        required={'@loader_path/.jbroot/usr/lib/libroothide.dylib',
                  '@loader_path/.jbroot/usr/lib/libsubstrate.dylib'}
        assert required.issubset(s['dependencies']),s['dependencies']
        assert all(d in required or d.startswith(('/usr/lib/','/System/Library/Frameworks/')) for d in s['dependencies']),s
        assert s['code_signature'],'Theos ldid ad-hoc signature missing'
    dst=OUT/'modules'/name;dst.parent.mkdir(exist_ok=True);shutil.copy2(path,dst)
    logs={}
    for label,cmd in [('architectures',['xcrun','lipo','-archs',str(dst)]),
                      ('load-commands',['xcrun','otool','-l',str(dst)]),
                      ('dependencies',['xcrun','otool','-L',str(dst)]),
                      ('symbols',['xcrun','nm','-m',str(dst)])]:
        text=subprocess.check_output(cmd,text=True,stderr=subprocess.STDOUT)
        report=OUT/(module+'-'+label+'.txt');report.write_text(text);logs[label]=report.name
    record['products'].append({'path':str(dst.relative_to(OUT)),'bytes':dst.stat().st_size,
        'sha256':hashlib.sha256(dst.read_bytes()).hexdigest(),'slices':info,'reports':logs,
        'signing':'ldid ad-hoc developer artifact, not device-load validated'})
record['toolchain']={}
for label,args in [('xcode',['xcodebuild','-version']),('clang',['xcrun','--sdk','iphoneos','clang','--version']),
                   ('swift',['xcrun','--sdk','iphoneos','swiftc','--version']),('sdk',['xcrun','--sdk','iphoneos','--show-sdk-version'])]:
    record['toolchain'][label]=subprocess.check_output(args,text=True,stderr=subprocess.STDOUT).strip()
THEOS=Path(os.environ['THEOS'])
record['theos_commits']={p:subprocess.check_output(['git','-C',str(THEOS/p),'rev-parse','HEAD'],text=True).strip()
                         for p in ('.','vendor/include','vendor/lib','vendor/dm.pl')}
(OUT/'manifest.json').write_text(json.dumps(record,indent=2))
print(json.dumps(record,indent=2))
