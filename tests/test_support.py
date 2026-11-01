"""Regression checks for manifests, selection and paths in desktop launchers."""
import importlib.util
import json
import os
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import contextlib
import shutil
import uuid
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('support', ROOT / 'linux/support.py')
support = importlib.util.module_from_spec(spec)
spec.loader.exec_module(support)


@contextlib.contextmanager
def test_directory():
    # mkdir's default permissions also work in restricted Windows test processes.
    base = Path(os.environ.get('STORYTOLD_TEST_TMP', tempfile.gettempdir())).resolve()
    path = base / ('storytold-test-' + uuid.uuid4().hex)
    path.mkdir(parents=True)
    try:
        yield str(path)
    finally:
        assert path.parent == base and path.name.startswith('storytold-test-')
        shutil.rmtree(path)


def decode_desktop_exec(value):
    # General desktop string unescaping happens before Exec argument parsing.
    value = value.replace('\\\\', '\\')
    return shlex.split(value)[0].replace('\\$', '$').replace('\\`', '`').replace('%%', '%')


class Tests(unittest.TestCase):
    def test_manifest(self):
        manifest = json.loads((ROOT / 'linux/apps.json').read_text())
        self.assertEqual(set(a['id'] for a in manifest['apps']), set(support.NAMES))
        for app in manifest['apps']:
            self.assertRegex(app['commit'], r'^[0-9a-f]{40}$')
            self.assertEqual(app['package'], app['binary'])
            self.assertTrue(app['apt'])
        solid = next(a for a in manifest['apps'] if a['id'] == 'solidcraft')
        self.assertEqual(solid['repo'], 'tangency-labs/solidcraft')

    def test_selected_dependencies(self):
        output = subprocess.check_output([sys.executable, str(ROOT / 'linux/support.py'),
                                          'packages', str(ROOT / 'linux/apps.json'), 'deckcraft'], text=True)
        self.assertIn('libasound2-dev', output.split())
        self.assertNotIn('qpdf', output.split())

    def test_unknown_id_fails(self):
        result = subprocess.run([sys.executable, str(ROOT / 'linux/support.py'),
                                 'packages', str(ROOT / 'linux/apps.json'), 'unknown'], capture_output=True)
        self.assertNotEqual(result.returncode, 0)

    def test_desktop_round_trip(self):
        with test_directory() as tmp:
            # Windows cannot create quotes in names, but they must work on Linux.
            suffixes = ['spaces and unicode é', 'dollar$ backtick` percent%']
            if os.name != 'nt':
                suffixes += ['double" single\' slash\\']
            for suffix in suffixes:
                data = Path(tmp) / suffix
                binary = str(data / 'apps/wordcraft')
                support.desktop(str(data), 'wordcraft', binary, '0')
                wrapper = data / 'storytold/launchers/wordcraft'
                entry = (data / 'applications/storytold-wordcraft.desktop').read_text(encoding='utf-8')
                value = next(line[5:] for line in entry.splitlines() if line.startswith('Exec='))
                self.assertEqual(decode_desktop_exec(value), str(wrapper))
                self.assertEqual(shlex.split(wrapper.read_text(encoding='utf-8').splitlines()[1])[1], binary)
                if os.name != 'nt':
                    subprocess.run(['desktop-file-validate', str(data / 'applications/storytold-wordcraft.desktop')], check=True)

    def test_disabled_desktop_does_not_write_home(self):
        with test_directory() as tmp:
            with patch.object(support.subprocess, 'check_output', return_value=str(Path.home())):
                support.desktop(tmp, 'cadcraft', '/example/cadcraft', '1')
            self.assertTrue((Path(tmp) / 'applications/storytold-cadcraft.desktop').exists())

    def test_desktop_copy(self):
        with test_directory() as tmp:
            desktop = Path(tmp) / 'Desktop'
            desktop.mkdir()
            with patch.object(support.subprocess, 'check_output', return_value=str(desktop)):
                support.desktop(str(Path(tmp) / 'data'), 'solidcraft', '/example/solidcraft', '1')
            self.assertTrue((desktop / 'storytold-solidcraft.desktop').exists())


if __name__ == '__main__':
    unittest.main()
