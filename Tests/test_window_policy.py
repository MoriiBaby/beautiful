"""Execute production main-window C policy on host; not a UIKit/device test."""
import ctypes as C
import itertools
from pathlib import Path
import platform,subprocess,tempfile,unittest
ROOT=Path(__file__).resolve().parents[1]
class Rect(C.Structure):_fields_=[(n,C.c_double) for n in ('x','y','width','height')]
def values(r):return tuple(getattr(r,n) for n,_ in r._fields_)
class WindowPolicyTests(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.temp=tempfile.TemporaryDirectory();p=Path(cls.temp.name)/'policy.so'
  cmd=['clang','-std=c11','-Wall','-Wextra','-Werror','-dynamiclib' if platform.system()=='Darwin' else '-shared','-fPIC',str(ROOT/'Sources/Main/SRWindowPolicy.c'),'-o',str(p),'-lm']
  if platform.system()=='Darwin':cmd+=['-isysroot',subprocess.check_output(['xcrun','--sdk','macosx','--show-sdk-path'],text=True).strip()]
  subprocess.run(cmd,check=True,capture_output=True);cls.lib=C.CDLL(str(p))
  cls.lib.SRWindowConstrain.argtypes=[Rect,Rect,C.POINTER(Rect)];cls.lib.SRWindowConstrain.restype=C.c_bool
  cls.lib.SRWindowResize.argtypes=[Rect,Rect,C.c_double,C.POINTER(Rect)];cls.lib.SRWindowResize.restype=C.c_bool
 @classmethod
 def tearDownClass(cls):cls.temp.cleanup()
 def test_output_unchanged_when_invalid(self):
  for bad in [Rect(0,0,0,1),Rect(0,0,1,-1),Rect(float('nan'),0,1,1),Rect(0,0,float('inf'),1)]:
   out=Rect(11,12,13,14);self.assertFalse(self.lib.SRWindowConstrain(bad,Rect(0,0,390,844),C.byref(out)));self.assertEqual(values(out),(11,12,13,14))
 def test_fully_clamped_on_main_screen(self):
  out=Rect();self.assertTrue(self.lib.SRWindowConstrain(Rect(-999,9999,900,300),Rect(0,0,390,844),C.byref(out)))
  self.assertEqual(values(out),(0,544,390,300))
 def test_tiny_and_offset_screen(self):
  out=Rect();self.assertTrue(self.lib.SRWindowConstrain(Rect(-90,-80,1,1),Rect(5,9,50,70),C.byref(out)))
  self.assertEqual(values(out),(5,9,50,70))
 def test_resize_failure_does_not_mutate_result(self):
  for scale in [0,-1,float('nan'),float('inf'),1e308]:
   out=Rect(1,2,3,4);self.assertFalse(self.lib.SRWindowResize(Rect(0,0,200,400),Rect(0,0,390,844),scale,C.byref(out)));self.assertEqual(values(out),(1,2,3,4))
 def test_drag_resize_grid_always_visible(self):
  for w,h,scale,x,y in itertools.product((320,390,844),(240,390,844),(.1,.5,1,2),(-900,0,900),(-900,0,900)):
   out=Rect();screen=Rect(0,0,w,h)
   self.assertTrue(self.lib.SRWindowResize(Rect(x,y,240,400),screen,scale,C.byref(out)))
   self.assertGreaterEqual(out.x,0);self.assertGreaterEqual(out.y,0)
   self.assertLessEqual(out.x+out.width,w);self.assertLessEqual(out.y+out.height,h)
if __name__=='__main__':unittest.main(verbosity=2)
