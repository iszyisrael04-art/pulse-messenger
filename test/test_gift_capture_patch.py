import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('capture_patch', ROOT / 'scripts/patch_webrtc_capture.py')
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

class CapturePatchTest(unittest.TestCase):
    def test_resolved_package_with_spaces_is_patched_once_and_unknown_version_refused(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            package = root / 'cache with spaces/flutter_webrtc'
            source = package / 'common/cpp/src/flutter_frame_capturer.cc'
            header = package / 'common/cpp/include/flutter_frame_capturer.h'
            source.parent.mkdir(parents=True); header.parent.mkdir(parents=True)
            old = 'while(!catch_frame_){}\nnew uint8_t[width * height * 4];\n'
            source.write_text(old); header.write_text('bool catch_frame_;')
            (package/'pubspec.yaml').write_text('version: 1.6.2+hotfix.4\n')
            (root/'.dart_tool').mkdir()
            (root/'.dart_tool/package_config.json').write_text(json.dumps({'packages':[
                {'name':'flutter_webrtc','rootUri':package.as_uri()+'/'}]}))
            self.assertTrue(module.patch(root))
            self.assertIn('frame_ready_.wait_for', source.read_text())
            self.assertNotIn('new uint8_t[', source.read_text())
            self.assertFalse(module.patch(root))
            source.write_text(old); header.write_text('bool catch_frame_;')
            (package/'pubspec.yaml').write_text('version: 1.7.0\n')
            with self.assertRaisesRegex(RuntimeError, 'Review Windows'):
                module.patch(root)
            self.assertEqual(source.read_text(), old)
