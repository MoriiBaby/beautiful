"""Source wiring checks, NOT execution of UIKit/Substrate. Pure policies run in test_policy.py."""
import hashlib
import json
from pathlib import Path
import re
import unittest

ROOT=Path(__file__).resolve().parents[1]
AUDIT=ROOT.parent/'stheno-audit-20261021'

def source(path): return (ROOT/path).read_text()
def body(text,name):
    # Balanced function body for our deliberately simple C/ObjC++ wrappers.
    m=re.search(r'\b'+re.escape(name)+r'\s*\([^;]*?\)\s*\{',text,re.S)
    if not m: raise AssertionError('missing function body '+name)
    start=m.end();depth=1
    for i in range(start,len(text)):
        if text[i]=='{':depth+=1
        if text[i]=='}':depth-=1
        if depth==0:return text[start:i]
    raise AssertionError('unbalanced '+name)

def keyboard_contract(text):
    active=body(text,'SRKeyboardActive')
    if active.index('SRKeyboardReadFrontmost()')>active.index('gActiveOriginal'):return False
    read=body(text,'SRKeyboardReadFrontmost')
    if '/tmp/stheno_frontmost.json' not in read or 'JSONObjectWithData' not in read:return False
    if 'writeToFile' in text or 'stheno_env' in text:return False
    if 'componentsSeparatedByString:@" "' not in text:return False
    window=body(text,'SRKeyboardWindow')
    for required in ['SRKeyboardShouldResize','[gFrontmost isEqualToString:gBundleID]',
                     'gHookScreen = NO','UIScreen.mainScreen.bounds','setFrame:', 'setBounds:',
                     '@finally','gHookScreen = YES']:
        if required not in window:return False
    if window.index('gHookScreen = NO')>window.index('UIScreen.mainScreen.bounds'):return False
    scene=body(text,'SRKeyboardScene')
    if 'SRKeyboardReload169()' not in scene or 'gFirstScene = scene' not in scene:return False
    bounds=body(text,'SRKeyboardBounds')
    if 'SRKeyboardShouldForwardBounds(gMode169, gHookScreen)' not in bounds:return False
    if 'SRCheckHookSignature(object_getClass(gFirstScene)' not in bounds:return False
    if 'ns_consumed' not in text or 'ns_returns_retained' not in text:return False
    if text.count('SRCheckHookSignature(')<6:return False
    return True

class SmallModuleWiring(unittest.TestCase):
    def test_keyboard_wiring_uses_corrected_original_contract(self):
        self.assertTrue(keyboard_contract(source('Sources/Keyboard/Keyboard.mm')))
    def test_negative_old_ipc_and_order_rejected(self):
        original=source('Sources/Keyboard/Keyboard.mm')
        mutations=[original.replace('stheno_frontmost.json','stheno_env.json'),
            original.replace('componentsSeparatedByString:@" "','componentsSeparatedByString:@","'),
            original.replace('gHookScreen = NO','gHookScreen = YES'),
            original.replace('setBounds:','setFrame:'),
            original.replace('SRKeyboardShouldForwardBounds(gMode169, gHookScreen)','(gMode169 || gHookScreen)'),
            original.replace('ns_consumed','unused'),
            original.replace('ns_returns_retained','unused')]
        for variant in mutations:
            self.assertNotEqual(variant,original)
            self.assertFalse(keyboard_contract(variant))
    def test_camera_missing_value_retains_cache_before_original(self):
        camera=source('Sources/Camera/Camera.mm')
        reload=body(camera,'SRCameraReload')
        self.assertLess(reload.index('if (!prefs || !value'),reload.index('SRStickyFlagNext'))
        update=body(camera,'SRCameraUpdate')
        self.assertLess(update.index('SRCameraReload()'),update.index('gCameraEnabled'))
        self.assertLess(update.index('gCameraEnabled'),update.index('original(receiver'))
        self.assertNotIn('dlopen',camera)
        self.assertIn('SRCameraTryInstall<long long>',camera)
        self.assertIn('SRCameraTryInstall<id>',camera)
    def test_camera_cannot_install_unknown_argument_abi(self):
        camera=source('Sources/Camera/Camera.mm')
        install=body(camera,'SRCameraTryInstall')
        self.assertLess(install.index('SRCheckHookSignature'),install.index('SRInstallHook'))
        self.assertIn('@encode(Condition)',install)
        self.assertNotIn('uintptr_t',camera)
    def test_runtime_exact_preflight_and_opt_in(self):
        runtime=source('Sources/Shared/SRRuntime.mm')
        for name in ['Stheno.dylib','SthenoCamera.dylib','SthenoKeyboard.dylib']:
            self.assertIn('"'+name+'"',runtime)
        activate=body(runtime,'SRRuntimeCanActivate')
        self.assertLess(activate.index('SRIsOriginalLoaded()'),activate.index('EnableReconstruction'))
        self.assertIn('isKindOfClass:NSNumber.class',activate)
        self.assertIn('return jbroot(path);',runtime)
        check=body(runtime,'SRCheckHookSignature')
        for item in ['method_getNumberOfArguments','method_copyReturnType','method_copyArgumentType',
                     'SRTypeEncodingMatches','free(actual)']:
            self.assertIn(item,check)
        self.assertNotIn('dlopen(',runtime)
    def test_scene_first_attach_then_window_visible(self):
        swift=source('Sources/Main/SRFloatingCoordinator.swift')
        start=swift.index('func attachAndPresent()')
        region=swift[start:swift.index('func bringForward()',start)]
        self.assertLess(region.index('guard SRMainSceneHostingAvailable()'),region.index('UIWindow(frame:'))
        self.assertLess(region.index('guard SRMainAttachScene('),region.index('window.isHidden = false'))
        self.assertIn('window.rootViewController = nil',region)
        self.assertNotIn('UIGraphicsImageRenderer',swift)
    def test_original_inputs_and_extracted_sources_unchanged(self):
        if not (AUDIT/'INPUT-MANIFEST.json').is_file():
            self.skipTest('Original audit not supplied; source-only checkout')
        manifest=json.loads((AUDIT/'INPUT-MANIFEST.json').read_text())
        for group,record in manifest.items():
            path=Path('/var/minis/attachments/uploads')/record['name']
            self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(),record['sha256'])
            for member in record['members']:
                if 'sha256' not in member:continue
                root=AUDIT/group
                if group=='deb':root/= 'control' if member['archive'].startswith('control') else 'data'
                self.assertEqual(hashlib.sha256((root/member['path']).read_bytes()).hexdigest(),member['sha256'])

if __name__=='__main__':unittest.main(verbosity=2)
