import importlib.util
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from run_lab import resolve_dart_executable


class TestDartResolution(unittest.TestCase):
    def test_explicit_executable_path(self):
        with tempfile.TemporaryDirectory() as t:
            dart = Path(t) / 'dart.exe'
            dart.write_bytes(b'placeholder')
            self.assertEqual(resolve_dart_executable(str(dart), Path(t)), str(dart.resolve()))

    def test_finds_dart_from_flutter_bin(self):
        with tempfile.TemporaryDirectory() as t:
            folder = Path(t) / 'flutter' / 'bin'
            sdk = folder / 'cache' / 'dart-sdk' / 'bin'
            sdk.mkdir(parents=True)
            flutter = folder / 'flutter.bat'
            flutter.write_bytes(b'placeholder')
            dart = sdk / 'dart.exe'
            dart.write_bytes(b'placeholder')
            def which(name):
                return str(flutter) if name == 'flutter' else None
            with mock.patch('shutil.which', side_effect=which):
                with mock.patch.dict(os.environ, {'FLUTTER_ROOT': ''}):
                    self.assertEqual(resolve_dart_executable(None, Path(t)), str(dart))

    def test_missing_dart_reports_actionable_error(self):
        with tempfile.TemporaryDirectory() as t:
            with self.assertRaisesRegex(FileNotFoundError, 'Dart executable not found'):
                resolve_dart_executable(str(Path(t) / 'no-dart.exe'), Path(t))

    def test_finds_project_local_fvm_dart(self):
        with tempfile.TemporaryDirectory() as t:
            repo = Path(t)
            mobile = repo/'apps'/'mobile'
            mobile.mkdir(parents=True)
            dart = repo/'.fvm'/'flutter_sdk'/'bin'/'cache'/'dart-sdk'/'bin'/'dart.exe'
            dart.parent.mkdir(parents=True)
            dart.write_bytes(b'placeholder')
            with mock.patch('shutil.which', return_value=None):
                with mock.patch.dict(os.environ, {'FLUTTER_ROOT': ''}):
                    self.assertEqual(resolve_dart_executable(None, mobile), str(dart))


if __name__ == '__main__':
    unittest.main()
