"""Validate the saved authorized metadata capture; NEVER connects or attaches."""
import json
from pathlib import Path
import unittest

ROOT=Path(__file__).resolve().parents[1]
CAPTURE=ROOT/'Device/Results/springboard-metadata-20261021T082940Z.json'

class DeviceMetadataEvidence(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not CAPTURE.is_file():raise unittest.SkipTest('Authorized device evidence not supplied')
        cls.capture=json.loads(CAPTURE.read_text())
        cls.classes={c['name']:c for c in cls.capture['metadata']['classes']}
    def method(self,cls,kind,selector):
        result=next(x for x in self.classes[cls]['methods'] if x['kind']==kind and x['selector']==selector)
        self.assertTrue(result['exists'])
        return result
    def assertABI(self,cls,kind,selector,result,args):
        m=self.method(cls,kind,selector)
        self.assertEqual(m['returnType'],result)
        self.assertEqual(m['arguments'],['@',':']+args)
    def test_capture_identity_cleanup_and_scope(self):
        r=self.capture
        self.assertEqual(r['os_version'],'16.0.3')
        self.assertEqual(r['status'],'COLLECTED')
        self.assertTrue(r['attached'] and r['script_unloaded'] and r['detached'])
        self.assertTrue(r['same_process_present'])
        self.assertEqual(r['pid_after'],[r['pid_before']])
        self.assertIn('no method bodies invoked',r['metadata']['scope'])
        js=(ROOT/'Device/collect_objc_metadata.js').read_text()
        for forbidden in ['Interceptor.attach(', 'Interceptor.replace(', 'ObjC.choose(',
                          'new ObjC.Object(', 'NativeCallback(', '.spawn(']:
            self.assertNotIn(forbidden,js)
    def test_keyboard_expected_signatures_match_measured_os16(self):
        self.assertABI('UIKeyboardAutomatic','class','activeInstance','@',[])
        self.assertABI('UIRemoteKeyboardWindow','class','remoteKeyboardWindowForScreen:create:','@',['@','B'])
        self.assertABI('UIScene','instance','initWithSession:connectionOptions:','@',['@','@'])
        for cls in ['UIScene','UIScreen']:
            self.assertABI(cls,'instance','_boundsForInterfaceOrientation:',
                           '{CGRect={CGPoint=dd}{CGSize=dd}}',['q'])
    def test_scene_layer_construction_abi_is_known_but_not_executed(self):
        self.assertABI('_UIContextLayerHostView','instance','initWithSceneLayer:','@',['@'])
        self.assertABI('_UIKeyboardLayerHostView','instance','initWithKeyboardLayer:owningScene:','@',['@','@'])
        self.assertABI('FBSSceneLayer','instance','isKeyboardLayer','B',[])
        self.assertABI('FBSceneManager','instance','enumerateScenesWithBlock:','v',['@?'])
        self.assertABI('FBScene','instance','updateSettings:withTransitionContext:completion:',
                       'v',['@','@','@?'])
    def test_no_scene_destroy_or_launch_was_executed_by_collector(self):
        # They may appear as selector strings for metadata, but not an ObjC message call.
        js=(ROOT/'Device/collect_objc_metadata.js').read_text()
        self.assertNotIn('objc_msgSend',js)
        self.assertNotIn('objc_msgSendSuper',js)
        self.assertNotIn('_killForReason',js)

if __name__=='__main__':unittest.main(verbosity=2)
