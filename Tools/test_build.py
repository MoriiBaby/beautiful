"""Build safety/unit checks; real-artifact checks explicitly skip if not built.
These checks do NOT constitute scene-hosting, Swift, injection, or device tests.
"""
import json, os, plistlib, subprocess, tempfile, unittest
from pathlib import Path
import deps, guard, macho
ROOT = deps.ROOT

class BuildSafetyTests(unittest.TestCase):
    def test_source_package_and_filter_guards(self):
        self.assertEqual(guard.check()['source_and_package_configuration'], 'PASS')
    def test_default_build_fails_incomplete_main(self):
        p = subprocess.run(['make', '--no-print-directory'], cwd=ROOT, capture_output=True, text=True)
        self.assertNotEqual(p.returncode, 0)
        self.assertIn('BLOCKED', p.stderr)
    def test_package_and_install_never_execute(self):
        for target in ('package', 'install', 'stage'):
            p = subprocess.run(['make', '--no-print-directory', target], cwd=ROOT, capture_output=True, text=True)
            self.assertNotEqual(p.returncode, 0)
            self.assertIn('disabled', p.stderr)
    def test_missing_sdk_has_actionable_nonzero_failure(self):
        with tempfile.TemporaryDirectory(prefix='stheno-empty-cache-') as cache:
            env = dict(os.environ, STHENO_CACHE=cache)
            p = subprocess.run(['python3', 'Tools/deps.py', 'verify'], cwd=ROOT, env=env, capture_output=True, text=True)
            self.assertNotEqual(p.returncode, 0)
            self.assertIn('make deps-fetch', p.stderr)
    def test_sdk_directory_name_is_not_misreported_metadata(self):
        lock = deps.load()['sdk']; sdk = deps.CACHE / lock['repository_cache'] / lock['subdir']
        if not sdk.exists(): self.skipTest('SDK not fetched; not an iOS validation result')
        actual = plistlib.loads((sdk / 'SDKSettings.plist').read_bytes())
        self.assertEqual(actual['Version'], lock['metadata_version'])
        self.assertEqual(actual['CanonicalName'], lock['canonical_name'])
    def test_architectures_are_not_dropped_for_lld(self):
        self.assertEqual(deps.load()['target']['architectures'], ['arm64', 'arm64e'])
        source = (ROOT / 'Tools/build.py').read_text()
        self.assertIn("ARCHS = ('arm64', 'arm64e')", source)
        self.assertNotIn('dynamic_lookup', source)
    def record(self):
        for rel in ('latest-link-small.json', 'latest-compile-small.json', 'latest-small.json'):
            pointer = ROOT / 'Tools/Build' / rel
            if pointer.exists(): return json.loads((ROOT / json.loads(pointer.read_text())['manifest']).read_text())
        self.skipTest('No local Mach-O evidence; no iOS build success is implied')
    def test_actual_objects_have_correct_subtype_and_minos(self):
        record = self.record(); seen = set(); count = 0
        for artifact in record['artifacts']:
            if artifact['path'].endswith('.o'):
                path = ROOT / artifact['path']; arch = artifact['macho'][0]['architecture']
                self.assertEqual(deps.sha(path), artifact['sha256'])
                macho.validate(path, [arch], 'object'); seen.add(arch); count += 1
        self.assertEqual(seen, {'arm64', 'arm64e'}); self.assertGreaterEqual(count, 8)
    def test_lld_downgrade_is_rejected_not_relabelled(self):
        record = self.record(); rejected = record.get('rejected_artifacts', [])
        if not rejected: self.skipTest('No downgraded link evidence recorded on this toolchain')
        for artifact in rejected:
            self.assertTrue(artifact['path'].endswith('.REJECTED'))
            self.assertEqual(artifact['expected_architecture'], 'arm64e')
            with self.assertRaises(ValueError):
                macho.validate(ROOT / artifact['path'], ['arm64e'], 'dylib')
        self.assertEqual(record['status'], 'FAILED')
        self.assertFalse(record['install_ready'])

if __name__ == '__main__': unittest.main()
