import ctypes as C
import itertools
import math
import platform
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]

class Rect(C.Structure):
    _fields_ = [(x, C.c_double) for x in ('x','y','width','height')]
class Geometry(C.Structure):
    _fields_ = [('frame',Rect), ('bounds',Rect)]
def values(r):
    return (r.x, r.y, r.width, r.height)

class ProductionPolicyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        clang = shutil.which('clang')
        if not clang:
            raise RuntimeError('clang required: tests compile the actual SRPolicy.c, not a Python model')
        cls.temp = tempfile.TemporaryDirectory(prefix='stheno-policy-')
        output = Path(cls.temp.name) / ('policy.dylib' if platform.system() == 'Darwin' else 'policy.so')
        linker_flag = '-dynamiclib' if platform.system() == 'Darwin' else '-shared'
        cmd = [clang, '-std=c11','-Wall','-Wextra','-Werror',linker_flag,'-fPIC',
               str(ROOT/'Sources/Shared/SRPolicy.c'),'-o',str(output)]
        if platform.system() == 'Darwin':
            cmd += ['-isysroot', subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'], text=True).strip()]
        run = subprocess.run(cmd,capture_output=True,text=True)
        if run.returncode:
            raise RuntimeError('Host C build failed:\n'+run.stderr)
        cls.lib = C.CDLL(str(output))
        for name,count in [('SRStickyFlagNext',4),('SRKeyboardShouldResize',2),
                           ('SRKeyboardShouldForwardBounds',2)]:
            f=getattr(cls.lib,name);f.argtypes=[C.c_bool]*count;f.restype=C.c_bool
        cls.lib.SRTypeEncodingMatches.argtypes=[C.c_char_p,C.c_char_p]
        cls.lib.SRTypeEncodingMatches.restype=C.c_bool
        cls.lib.SRKeyboardGeometryForScreen.argtypes=[Rect]
        cls.lib.SRKeyboardGeometryForScreen.restype=Geometry
    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()
    def test_sticky_flag_all_16_input_combinations(self):
        for previous,prefs,key,value in itertools.product([False,True],repeat=4):
            actual=self.lib.SRStickyFlagNext(previous,prefs,key,value)
            self.assertEqual(actual,value if prefs and key else previous)
    def test_enable_then_missing_then_explicit_disable(self):
        state=False
        for prefs,key,value,expected in [(True,True,True,True),(False,False,False,True),
                                         (True,False,False,True),(True,True,False,False)]:
            state=self.lib.SRStickyFlagNext(state,prefs,key,value)
            self.assertEqual(state,expected)
    def test_resize_condition_ccmp_polarity(self):
        for window,matches in itertools.product([False,True],repeat=2):
            self.assertEqual(self.lib.SRKeyboardShouldResize(window,matches), window and not matches)
    def test_screen_forward_requires_both_not_or(self):
        for mode,hook in itertools.product([False,True],repeat=2):
            self.assertEqual(self.lib.SRKeyboardShouldForwardBounds(mode,hook),mode and hook)
    def test_portrait_and_square_keep_exact_input_bounds(self):
        for raw in [(0,0,390,844),(0,0,400,400),(3,7,390,844),(0,0,0,0)]:
            result=self.lib.SRKeyboardGeometryForScreen(Rect(*raw))
            self.assertEqual(values(result.frame),raw)
            self.assertEqual(values(result.bounds),raw)
    def test_landscape_centered_square_and_zero_bounds_origin(self):
        for raw,frame,bounds in [((0,0,844,390),(227,0,390,390),(0,0,390,390)),
              ((7,11,1024,768),(128,0,768,768),(0,0,768,768)),
              ((0,0,10,0),(5,0,0,0),(0,0,0,0))]:
            result=self.lib.SRKeyboardGeometryForScreen(Rect(*raw))
            self.assertEqual(values(result.frame),frame)
            self.assertEqual(values(result.bounds),bounds)
    def test_finite_geometry_grid(self):
        for w in range(100,2101,40):
            for h in range(100,2101,40):
                g=self.lib.SRKeyboardGeometryForScreen(Rect(0,0,w,h))
                if w>h:
                    self.assertEqual(g.frame.width,h)
                    self.assertEqual(g.frame.x*2+g.frame.width,w)
                    self.assertEqual(g.bounds.width,g.bounds.height)
                else:
                    self.assertEqual(values(g.frame),(0,0,w,h))
    def test_objc_encoding_matching_without_erasing_abi(self):
        match=self.lib.SRTypeEncodingMatches
        for a,b in [(b'v',b'v'),(b'rq',b'q'),(b'@"UIView"',b'@'),
                    (b'@',b'@"NSObject"'),(b'@?',b'@?'),(b'^v',b'^v')]:
            self.assertTrue(match(a,b),(a,b))
        for a,b in [(b'q',b'i'),(b'Q',b'q'),(b'B',b'c'),(b'@?',b'@'),
                    (b'^v',b'@'),(b'{CGRect=dddd}',b'@'),(None,b'@'),(b'',b'@'),
                    (b'@"Broken',b'@')]:
            self.assertFalse(match(a,b),(a,b))

if __name__=='__main__':
    unittest.main(verbosity=2)
