"""Host tests of the SAME production C policy used by SRSceneSession.mm.

Compiles only owned portable C; no device, ObjC runtime, SDK edits or Python
state-machine substitute. Source checks are labelled wiring, not UIKit tests.
"""
import ctypes as C
import itertools
import math
from pathlib import Path
import platform
import random
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
BRIDGE = ROOT / 'Sources/Main/SceneBridge'
IDLE, ACQUIRING, ACTIVATING, LAYERS, ATTACHED, CLOSING, CLOSED = range(7)
UNTOUCHED, PENDING, OWNED, RESTORING, RESTORED, UNRESOLVED = range(6)
WAIT, FINISH, RESTORE, UNSAFE = range(4)


class Policy(C.Structure):
    _fields_ = [('generation', C.c_uint64), ('pending_generation', C.c_uint64),
                ('deadline', C.c_double), ('phase', C.c_int), ('foreground', C.c_int),
                ('start_delivered', C.c_bool), ('close_delivered', C.c_bool)]


class ProductionSessionPolicy(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        compiler = shutil.which('clang') or shutil.which('cc')
        if not compiler:
            raise RuntimeError('C compiler required; no model fallback is permitted')
        cls.temp = tempfile.TemporaryDirectory(prefix='stheno-session-policy-')
        darwin = platform.system() == 'Darwin'
        output = Path(cls.temp.name) / ('policy.dylib' if darwin else 'policy.so')
        command = [compiler, '-std=c11', '-Wall', '-Wextra', '-Werror', '-pedantic',
                   '-dynamiclib' if darwin else '-shared', '-fPIC',
                   str(BRIDGE / 'SRSessionPolicy.c'), '-o', str(output)]
        if darwin:
            sdk = subprocess.check_output(['xcrun', '--sdk', 'macosx', '--show-sdk-path'], text=True).strip()
            command += ['-isysroot', sdk]
        result = subprocess.run(command, capture_output=True, text=True)
        if result.returncode:
            cls.temp.cleanup()
            raise RuntimeError('Production C did not compile:\n' + result.stderr)
        cls.lib = C.CDLL(str(output))
        ptr = C.POINTER(Policy)
        cls.lib.SRSessionPolicyInit.argtypes = [ptr]
        cls.lib.SRSessionPolicyInit.restype = None
        signatures = {
            'Begin': [ptr, C.c_double, C.c_double],
            'Accept': [ptr, C.c_uint64], 'Expired': [ptr, C.c_double],
            'Acquired': [ptr, C.c_uint64, C.c_bool, C.c_bool],
            'ExpectsCallback': [ptr, C.c_uint64, C.c_bool],
            'CompleteForeground': [ptr, C.c_uint64, C.c_bool, C.c_bool],
            'Attach': [ptr, C.c_uint64], 'BeginClose': [ptr, C.c_double, C.c_double],
            'ObserveForegroundAbsent': [ptr, C.c_bool], 'BeginRestore': [ptr],
            'FinishClose': [ptr, C.c_bool], 'TakeStartCompletion': [ptr],
            'TakeCloseCompletion': [ptr],
        }
        for suffix, args in signatures.items():
            function = getattr(cls.lib, 'SRSessionPolicy' + suffix)
            function.argtypes, function.restype = args, C.c_bool
        cls.lib.SRSessionPolicyRollback.argtypes = [ptr, C.c_double, C.c_bool, C.c_bool, C.c_bool]
        cls.lib.SRSessionPolicyRollback.restype = C.c_int
        cls.lib.SRSessionPolicySelect.argtypes = [C.c_size_t, C.c_bool]
        cls.lib.SRSessionPolicySelect.restype = C.c_int
        cls.lib.SRSessionPolicyUnresolved.argtypes = [ptr]
        cls.lib.SRSessionPolicyUnresolved.restype = None

    @classmethod
    def tearDownClass(cls):
        cls.temp.cleanup()

    def call(self, suffix, policy, *args):
        return getattr(self.lib, 'SRSessionPolicy' + suffix)(C.byref(policy), *args)

    def new(self):
        p = Policy()
        self.lib.SRSessionPolicyInit(C.byref(p))
        self.assertTrue(self.call('Begin', p, 100.0, 1.0))
        return p

    def owned(self):
        p = self.new()
        self.assertTrue(self.call('Acquired', p, p.generation, False, True))
        self.assertTrue(self.call('CompleteForeground', p, p.generation, False, True))
        self.assertTrue(self.call('Attach', p, p.generation))
        return p

    def test_01_invalid_intervals_and_single_admitted_start(self):
        for now, duration in [(-1, 1), (math.nan, 1), (math.inf, 1), (0, 0),
                              (0, .049), (0, 30.001), (0, math.nan), (0, math.inf)]:
            p = Policy()
            self.assertFalse(self.call('Begin', p, now, duration))
            self.assertEqual((p.generation, p.phase), (0, IDLE))
        for duration in [.05, 1, 30]:
            p = Policy()
            self.assertTrue(self.call('Begin', p, 0, duration))
            self.assertFalse(self.call('Begin', p, 0, duration))

    def test_02_selection_never_chooses_first_of_many(self):
        for matches in [0, 1, 2, 3, 10000]:
            for same in [False, True]:
                expected = 0 if matches == 0 else 2 if matches > 1 else 1 if same else 3
                self.assertEqual(self.lib.SRSessionPolicySelect(matches, same), expected)

    def test_03_background_mutation_requires_proof_and_generation(self):
        p = self.new()
        for generation, proof in [(0, True), (2, True), (1, False)]:
            self.assertFalse(self.call('Acquired', p, generation, False, proof))
            self.assertEqual((p.phase, p.foreground), (ACQUIRING, UNTOUCHED))
        self.assertTrue(self.call('Acquired', p, 1, False, True))
        self.assertEqual((p.phase, p.foreground), (ACTIVATING, PENDING))
        self.assertFalse(self.call('Attach', p, 1))
        self.assertFalse(self.call('CompleteForeground', p, 2, False, True))
        self.assertFalse(self.call('CompleteForeground', p, 1, True, True))
        self.assertTrue(self.call('CompleteForeground', p, 1, False, True))
        self.assertEqual((p.phase, p.foreground), (LAYERS, OWNED))
        self.assertFalse(self.call('CompleteForeground', p, 1, False, True))
        self.assertTrue(self.call('Attach', p, 1))
        self.assertFalse(self.call('Attach', p, 1))

    def test_04_already_foreground_is_never_owned_or_rolled_back(self):
        p = self.new()
        self.assertTrue(self.call('Acquired', p, 1, True, False))
        self.assertTrue(self.call('Attach', p, 1))
        self.assertEqual(p.foreground, UNTOUCHED)
        self.assertTrue(self.call('BeginClose', p, 101, 2))
        self.assertEqual(self.call('Rollback', p, 101, False, True, False), FINISH)
        self.assertFalse(self.call('BeginRestore', p))
        self.assertTrue(self.call('FinishClose', p, False))

    def test_05_cancel_during_acquire_wait_layers_and_attached(self):
        for phase in [ACQUIRING, LAYERS, ATTACHED]:
            p = self.new()
            if phase != ACQUIRING:
                self.call('Acquired', p, 1, True, False)
            if phase == ATTACHED:
                self.call('Attach', p, 1)
            self.assertTrue(self.call('BeginClose', p, 100.5, 2))
            self.assertFalse(self.call('Accept', p, 1))
            self.assertFalse(self.call('Attach', p, 1))
            self.assertFalse(self.call('BeginClose', p, 100.6, 2))
            self.assertEqual(p.deadline, 102.5)
            self.assertTrue(self.call('FinishClose', p, False))
            self.assertFalse(self.call('Begin', p, 110, 1))

    def test_06_cancel_pending_ack_may_only_advance_cleanup(self):
        p = self.new()
        self.call('Acquired', p, 1, False, True)
        self.call('BeginClose', p, 100.5, 2)
        close_generation = p.generation
        self.assertEqual(self.call('Rollback', p, 100.6, True, True, True), WAIT)
        self.assertTrue(self.call('CompleteForeground', p, 1, False, True))
        self.assertEqual((p.phase, p.generation, p.foreground), (CLOSING, close_generation, OWNED))
        self.assertFalse(self.call('Attach', p, 1))
        self.assertFalse(self.call('Attach', p, close_generation))
        self.assertEqual(self.call('Rollback', p, 100.7, True, True, True), RESTORE)
        self.assertTrue(self.call('BeginRestore', p))
        self.assertFalse(self.call('CompleteForeground', p, 1, True, True))
        self.assertTrue(self.call('CompleteForeground', p, close_generation, True, True))
        self.assertEqual(self.call('Rollback', p, 100.8, True, False, True), FINISH)
        self.assertTrue(self.call('FinishClose', p, False))

    def test_07_rollback_identity_field_ownership_and_deadline_matrix(self):
        for identity, foreground, proof, expired in itertools.product([False, True], repeat=4):
            p = self.owned()
            self.call('BeginClose', p, 101, 2)
            now = 103 if expired else 102
            actual = self.call('Rollback', p, now, identity, foreground, proof)
            expected = UNSAFE if not identity else FINISH if not foreground else (
                RESTORE if proof and not expired else UNSAFE)
            self.assertEqual(actual, expected, (identity, foreground, proof, expired))
            # Owned is not itself evidence of a completed restoration.
            self.assertFalse(self.call('FinishClose', p, False))

    def test_08_no_write_when_another_actor_already_restored_no(self):
        p = self.owned()
        self.call('BeginClose', p, 101, 2)
        self.assertEqual(self.call('Rollback', p, 102, True, False, False), FINISH)
        self.assertFalse(self.call('ObserveForegroundAbsent', p, False))
        self.assertTrue(self.call('ObserveForegroundAbsent', p, True))
        self.assertEqual(p.foreground, RESTORED)
        self.assertFalse(self.call('BeginRestore', p))
        self.assertTrue(self.call('FinishClose', p, False))

    def test_09_timeout_pending_write_is_unresolved_no_late_resurrection(self):
        for restoring in [False, True]:
            p = self.owned() if restoring else self.new()
            if not restoring:
                self.call('Acquired', p, 1, False, True)
            self.call('BeginClose', p, 101, 2)
            if restoring:
                self.call('BeginRestore', p)
            sent = p.pending_generation
            self.assertEqual(self.call('Rollback', p, 102.999, True, True, True), WAIT)
            self.assertEqual(self.call('Rollback', p, 103, True, True, True), UNSAFE)
            self.assertFalse(self.call('FinishClose', p, False))
            self.assertTrue(self.call('FinishClose', p, True))
            terminal = bytes(p)
            for _ in range(5):
                self.assertFalse(self.call('CompleteForeground', p, sent, restoring, True))
                self.assertFalse(self.call('Attach', p, sent))
                self.assertFalse(self.call('ExpectsCallback', p, sent, restoring))
            self.assertEqual(bytes(p), terminal)

    def test_10_failed_proof_acknowledgement_never_owns_field(self):
        p = self.new()
        self.call('Acquired', p, 1, False, True)
        self.assertTrue(self.call('CompleteForeground', p, 1, False, False))
        self.assertEqual(p.foreground, UNRESOLVED)
        self.assertFalse(self.call('Attach', p, 1))
        self.call('BeginClose', p, 101, 2)
        self.assertEqual(self.call('Rollback', p, 101, True, True, True), UNSAFE)
        self.assertFalse(self.call('BeginRestore', p))
        self.assertTrue(self.call('FinishClose', p, True))

    def test_11_completions_can_be_claimed_only_once_in_delivery_phase(self):
        p = self.new()
        self.assertFalse(self.call('TakeStartCompletion', p))
        self.assertFalse(self.call('TakeCloseCompletion', p))
        self.call('Acquired', p, 1, True, False)
        self.assertFalse(self.call('TakeStartCompletion', p))
        self.call('Attach', p, 1)
        self.assertTrue(self.call('TakeStartCompletion', p))
        for _ in range(10):
            self.assertFalse(self.call('TakeStartCompletion', p))
        self.call('BeginClose', p, 102, 2)
        self.assertFalse(self.call('TakeCloseCompletion', p))
        self.call('FinishClose', p, False)
        self.assertTrue(self.call('TakeCloseCompletion', p))
        self.assertFalse(self.call('TakeCloseCompletion', p))
        self.assertFalse(self.call('TakeStartCompletion', p))

    def test_12_deadlines_are_inclusive_and_attached_is_not_start_timed_out(self):
        p = self.new()
        self.assertFalse(self.call('Expired', p, 100.999))
        self.assertTrue(self.call('Expired', p, 101))
        self.call('Acquired', p, 1, True, False)
        self.call('Attach', p, 1)
        self.assertFalse(self.call('Expired', p, 100000))
        self.call('BeginClose', p, 102, 2)
        self.assertFalse(self.call('Expired', p, 103.999))
        self.assertTrue(self.call('Expired', p, 104))

    def test_13_generation_never_wraps_and_closed_is_absorbing(self):
        p = Policy()
        p.generation = (1 << 64) - 1
        self.assertFalse(self.call('Begin', p, 100, 1))
        self.assertTrue(self.call('BeginClose', p, 100, 2))
        self.assertTrue(self.call('FinishClose', p, False))
        self.assertEqual(p.generation, (1 << 64) - 1)
        self.assertFalse(self.call('Accept', p, p.generation))
        self.assertFalse(self.call('BeginClose', p, 101, 2))
        self.assertFalse(self.call('BeginRestore', p))

    def test_14_random_duplicate_late_callbacks_after_terminal_do_nothing(self):
        rng = random.Random(160003)
        for _ in range(200):
            p = self.new()
            if rng.choice([False, True]):
                self.call('Acquired', p, 1, False, True)
            self.call('BeginClose', p, 101, 2)
            self.call('FinishClose', p, True)
            terminal = bytes(p)
            for _ in range(20):
                g = rng.randrange(0, 6)
                self.assertFalse(self.call('CompleteForeground', p, g, rng.choice([False, True]), True))
                self.assertFalse(self.call('Acquired', p, g, True, True))
                self.assertFalse(self.call('Attach', p, g))
            self.assertEqual(bytes(p), terminal)

    def test_15_null_inputs_are_fail_closed(self):
        self.assertFalse(self.lib.SRSessionPolicyBegin(None, 0, 1))
        self.assertFalse(self.lib.SRSessionPolicyAccept(None, 1))
        self.assertEqual(self.lib.SRSessionPolicyRollback(None, 0, True, True, True), UNSAFE)
        self.assertFalse(self.lib.SRSessionPolicyFinishClose(None, True))


class SessionSourceWiringOnly(unittest.TestCase):
    def test_objcpp_consumes_production_c_and_exact_typed_private_calls(self):
        source = (BRIDGE / 'SRSceneSession.mm').read_text()
        for function in ['Begin', 'Select', 'Acquired', 'Accept', 'ExpectsCallback',
                         'CompleteForeground', 'Attach', 'BeginClose', 'Rollback',
                         'ObserveForegroundAbsent', 'BeginRestore', 'FinishClose',
                         'TakeStartCompletion', 'TakeCloseCompletion']:
            if function == 'Accept':
                continue  # Called by C transitions, not duplicated in ObjC++.
            self.assertIn('SRSessionPolicy' + function + '(', source)
        for abi in ['v24@0:8@?16', 'v40@0:8@16@24@?32', 'B28@0:8@16B24']:
            self.assertIn('"' + abi + '"', source)
        self.assertIn('typedef void (^SRSessionEnumeratedScene)(id);', source)
        self.assertIn('NSOrderedSet.class', source)
        self.assertIn('!SRLayerHostCandidate.labEnabled', source)
        self.assertIn('os.majorVersion != 16 || os.minorVersion != 0 || os.patchVersion != 3', source)
        self.assertIn('beginGuardRestoring:YES', source)
        self.assertIn('ownsForegroundChange', source)
        self.assertIn('frontmostIdentityKnown', source)
        for forbidden in ['performSelector:', 'objc_msgSend(', 'Interceptor.', '_killForReason:',
                          'deactivateWithTransitionContext:', 'destroyScene', 'SRInstallHook(']:
            self.assertNotIn(forbidden, source)
        old_header = (BRIDGE / 'SRSceneHost.h').read_text()
        self.assertIn('#define SR_SCENE_HOSTING_IMPLEMENTED 0', old_header)


if __name__ == '__main__':
    unittest.main(verbosity=2)
