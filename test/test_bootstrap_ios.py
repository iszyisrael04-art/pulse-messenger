"""Exercise generated iOS configuration without downloading or invoking Flutter."""
import json
import plistlib
import runpy
import shutil
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]

class IOSBootstrapTest(unittest.TestCase):
    def test_runner_permissions_icon_sizes_and_idempotent_bridge(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root/'scripts').mkdir()
            shutil.copy(ROOT/'scripts/bootstrap_ios.py', root/'scripts/bootstrap_ios.py')
            (root/'native/ios').mkdir(parents=True)
            shutil.copy(ROOT/'native/ios/PulseNativeEditor.swift', root/'native/ios/PulseNativeEditor.swift')
            runner = root/'ios/Runner'
            assets = runner/'Assets.xcassets/AppIcon.appiconset'
            assets.mkdir(parents=True)
            (runner/'Info.plist').write_bytes(plistlib.dumps({}))
            (runner/'AppDelegate.swift').write_text('GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)\n')
            project = root/'ios/Runner.xcodeproj'
            project.mkdir()
            (project/'project.pbxproj').write_text('IPHONEOS_DEPLOYMENT_TARGET = 13.0;')
            (root/'ios/Podfile').write_text("# platform :ios, '13.0'")
            (assets/'Contents.json').write_text(json.dumps({'images': [{'filename':'test.png','size':'60x60','scale':'3x'}]}))
            (root/'test').mkdir()
            sample = root/'test/widget_test.dart'
            sample.write_text('MyApp counter template')
            with patch('subprocess.run') as command:
                runpy.run_path(str(root/'scripts/bootstrap_ios.py'))
                runpy.run_path(str(root/'scripts/bootstrap_ios.py'))
            text = (runner/'AppDelegate.swift').read_text()
            self.assertEqual(text.count('final class PulseIOSNativeEditor'), 1)
            self.assertEqual(text.count('PulseIOSNativeEditor.register(with:'), 1)
            self.assertTrue((root/'build/ios/SourcePackages').is_dir())
            self.assertFalse(sample.exists())
            info = plistlib.loads((runner/'Info.plist').read_bytes())
            self.assertEqual(info['CFBundleDisplayName'], 'Pulse')
            self.assertIn('NSPhotoLibraryAddUsageDescription', info)
            self.assertFalse(info['FirebaseMessagingAutoInitEnabled'])
            self.assertIn('15.0', (project/'project.pbxproj').read_text())
            self.assertIn('180', command.call_args_list[1].args[0])

if __name__ == '__main__':
    unittest.main()
