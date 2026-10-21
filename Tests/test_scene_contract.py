"""Source guards + independent arm64e fixup evidence, NOT an iOS runtime test."""
from pathlib import Path
import hashlib
import struct
import unittest

ROOT = Path(__file__).resolve().parents[1]
AUDIT = ROOT.parent / "stheno-audit-20261021"
BINARY = AUDIT / "deb/data/Library/MobileSubstrate/DynamicLibraries/Stheno.dylib"
SHA256 = "5fc39b0968bd282ba2be0c80909f6ba8aa0d22b9a904c1eebd41bca8ca9f82b7"


class SceneImage:
    """Only the observed Mach-O + DYLD_CHAINED_PTR_ARM64E_USERLAND24 format.

    Walk actual chain starts, not arbitrary high-bit masking. Import ordinals are
    24 bits, next is 11 bits * 8 bytes; auth rebase targets are 32-bit offsets.
    """
    def __init__(self, fat):
        assert fat[:4] == bytes.fromhex("cafebabe")
        arches = [struct.unpack_from(">iiIII", fat, 8 + i * 20)
                  for i in range(struct.unpack_from(">I", fat, 4)[0])]
        arch = next(a for a in arches if a[1] & 0xffffff == 2)
        self.data = fat[arch[2]:arch[2] + arch[3]]
        self.segments, self.sections, self.pointers = [], {}, {}
        pos = 32
        fixup = None
        for _ in range(self.u32(16)):
            cmd, size = struct.unpack_from("<II", self.data, pos)
            if cmd == 0x19:
                name = self.data[pos + 8:pos + 24].split(b"\0")[0].decode()
                va, vs, off, fs = struct.unpack_from("<QQQQ", self.data, pos + 24)
                self.segments.append((name, va, vs, off, fs))
                for i in range(self.u32(pos + 64)):
                    s = pos + 72 + i * 80
                    sn = self.data[s:s + 16].split(b"\0")[0].decode()
                    self.sections[sn] = struct.unpack_from("<QQI", self.data, s + 32)
            elif cmd == 0x80000034:
                fixup = self.u32(pos + 8)
            pos += size
        base = next(s[1] for s in self.segments if s[0] == "__TEXT")
        ver, starts, imp, syms, count, fmt, symfmt = struct.unpack_from(
            "<7I", self.data, fixup)
        assert ver == symfmt == 0 and fmt == 1
        names = [self.cstring(fixup + syms + (self.u32(fixup + imp + i * 4) >> 9))
                 for i in range(count)]
        starts += fixup
        self.formats = set()
        for si in range(self.u32(starts)):
            info = self.u32(starts + 4 + si * 4)
            if not info:
                continue
            p = starts + info
            _, ps, pf, seg, _, pages = struct.unpack_from("<IHHQIH", self.data, p)
            self.formats.add(pf)
            assert pf == 12
            for page in range(pages):
                start = self.u16(p + 22 + 2 * page)
                if start == 0xffff:
                    continue
                # Fail rather than silently mishandle an unobserved multi-start.
                assert start & 0x8000 == 0
                va = base + seg + page * ps + start
                seen = set()
                while True:
                    assert va not in seen
                    seen.add(va)
                    raw = self.u64(self.offset(va))
                    auth, bind = raw >> 63, (raw >> 62) & 1
                    if bind:
                        target = names[raw & 0xffffff]
                    elif auth:
                        target = base + (raw & 0xffffffff)
                    else:
                        target = base + (raw & ((1 << 43) - 1)) + (((raw >> 43) & 255) << 56)
                    self.pointers[va] = target
                    step = (raw >> 51) & 0x7ff
                    if not step:
                        break
                    va += step * 8

    def u16(self, p):
        return struct.unpack_from("<H", self.data, p)[0]

    def u32(self, p):
        return struct.unpack_from("<I", self.data, p)[0]

    def u64(self, p):
        return struct.unpack_from("<Q", self.data, p)[0]

    def offset(self, va):
        for _, v, _, off, size in self.segments:
            if v <= va < v + size:
                return off + va - v
        raise ValueError(hex(va))

    def cstring(self, p):
        return self.data[p:self.data.index(0, p)].decode()

    def selector(self, va):
        return self.cstring(self.offset(self.pointers[va]))

    def objc_methods(self, cls):
        pointer = lambda va: self.pointers.get(va, self.u64(self.offset(va)))
        relative = lambda va: va + struct.unpack_from("<i", self.data, self.offset(va))[0]
        # Only ObjC class-data low flag bits are cleared, never PAC pointer bits.
        ro = pointer(cls + 32) & ~7
        methods = pointer(ro + 32)
        flags, count = struct.unpack_from("<II", self.data, self.offset(methods))
        result = {}
        for i in range(count):
            entry = methods + 8 + i * (flags & 0xfffc)
            if flags & 0x80000000:
                name = relative(entry)
                if not flags & 0x40000000:
                    name = pointer(name)
                types, implementation = relative(entry + 4), relative(entry + 8)
            else:
                name, types, implementation = [pointer(entry + x) for x in (0, 8, 16)]
            result[self.cstring(self.offset(name))] = (self.cstring(self.offset(types)), implementation)
        return result

    def bl_target(self, va):
        op = self.u32(self.offset(va))
        assert op & 0xfc000000 == 0x94000000
        imm = op & 0x3ffffff
        if imm & 0x2000000:
            imm -= 0x4000000
        return va + imm * 4


class SceneContract(unittest.TestCase):
    def test_unavailable_source_contract(self):
        path = ROOT / "Sources/Main/SceneBridge"
        h = (path / "SRSceneHost.h").read_text()
        mm = (path / "SRSceneHost.mm").read_text()
        self.assertIn("#define SR_SCENE_HOSTING_IMPLEMENTED 0", h)
        for fragment in ("+ (BOOL)isAvailable { return NO; }",
                         "- (BOOL)isAttached { return NO; }",
                         "- (UIView *)hostedView { return nil; }"):
            self.assertIn(fragment, mm)
        self.assertEqual(mm.count("SRSceneHostErrorUnavailable, SRSceneHost.unavailableReason"), 2)
        self.assertEqual(mm.count("if (!SRRequireMainThread(error)) return NO;"), 3)
        for forbidden in ("objc_msgSend", "NSClassFromString", "MSHook", "dlopen",
                          "UIWindow", "addSubview:", "UIImage", "_killForReason"):
            self.assertNotIn(forbidden, mm)

    def test_disabled_candidate_is_separate_and_ownership_typed(self):
        path = ROOT / "Sources/Main/SceneBridge"
        h = (path / "SRLayerHostCandidate.h").read_text()
        mm = (path / "SRLayerHostCandidate.mm").read_text()
        main = (path / "SRSceneHost.mm").read_text()
        self.assertIn("#define SR_ENABLE_LAYER_HOST_LAB 0", h)
        self.assertNotIn("SRLayerHostCandidate", main)
        self.assertEqual(mm.count("__attribute__((ns_returns_retained))"), 3)
        self.assertEqual(mm.count("__attribute__((ns_consumed))"), 2)
        for required in ("method_copyReturnType", "method_copyArgumentType",
                         "method_getImplementation", "method_getNumberOfArguments",
                         "[argument isKindOfClass:parameterClass]", "@encode(BOOL)",
                         "((SRLabInitOne)implementation)", "((SRLabInitTwo)implementation)",
                         "SRLabCheckedIMP(allocation, initSelector", "view.superview || view.window",
                         "_retainedLayers = retained", "view.transform = transform",
                         "dispatch_async(dispatch_get_main_queue()"):
            self.assertIn(required, mm)
        for forbidden in ('@"setForeground:"', '@"launchApplication', '@"_killForReason',
                          'objc_msgSend', 'MSHook', 'dlopen', 'UIWindow', 'UIImage'):
            self.assertNotIn(forbidden, mm)
        self.assertEqual(mm.count("if (!SRLabMain(error)) return NO;"), 3)
        self.assertEqual(mm.count("if (!SRLayerHostCandidate.labEnabled)"), 2)

    def test_original_fixups_and_lifecycle_edges(self):
        if not BINARY.exists():
            self.skipTest("Original audit not supplied; source-only checkout")
        fat = BINARY.read_bytes()
        self.assertEqual(hashlib.sha256(fat).hexdigest(), SHA256)
        image = SceneImage(fat)
        self.assertEqual(image.formats, {12})
        expected = {
            0xa62a8: "_createSceneWithDefinition:settings:initialClientSettings:transitionContext:fromRemnant:usingClientProvider:completion:",
            0xa6330: "client:didUpdateClientSettings:withDiff:transitionContext:",
            0xa62c8: "_scene:interceptUpdateWithNewSettings:",
            0xa62d0: "_setDeactivationReasons:onScene:withSettings:reason:",
        }
        for slot, selector in expected.items():
            self.assertEqual(image.selector(slot), selector)
        self.assertEqual(image.pointers[0xa6670], "_OBJC_CLASS_$_FBScene")
        self.assertEqual(image.pointers[0xa6678], "_OBJC_CLASS_$_UIMutableApplicationSceneSettings")
        for slot, signature in ((0x9e1e0, "v8@?0"),
                                (0x9e730, 'v16@?0@"FBScene"8')):
            self.assertEqual(image.selector(slot), signature)
        self.assertEqual(image.objc_methods(0xa6810)["hitTest:withEvent:"],
                         ("@40@0:8{CGPoint=dd}16@32", 0x104f0))
        edges = {0x157ac: 0x2ba24, 0x156b0: 0x59194,
                 0x60d88: 0x76fd8, 0x611bc: 0x14184,
                 0x142dc: 0x590a8, 0x14fc8: 0x5963c,
                 0x5f784: 0x14d9c, 0x77654: 0x7ec60,
                 0x1053c: 0x103dc, 0x70bf0: 0x7ec20}
        for caller, callee in edges.items():
            self.assertEqual(image.bl_target(caller), callee)


if __name__ == "__main__":
    unittest.main()
