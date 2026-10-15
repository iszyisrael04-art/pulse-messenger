"""Checks native configuration without invoking Flutter or downloading an SDK."""
import runpy
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

SOURCE = Path(__file__).resolve().parents[1] / 'scripts/bootstrap.py'
class NativeConfigurationTest(unittest.TestCase):
    def test_windows_batch_resolution_and_idempotent_configuration(self):
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            script = root / 'scripts/bootstrap.py'
            script.parent.mkdir()
            script.write_text(SOURCE.read_text())
            manifest = root / 'android/app/src/main/AndroidManifest.xml'
            manifest.parent.mkdir(parents=True)
            manifest.write_text('<manifest><application android:label="pulse_messenger"></application><queries><intent/></queries></manifest>')
            gradle = root / 'android/app/build.gradle.kts'
            gradle.write_text('android {\n compileOptions {\n sourceCompatibility = JavaVersion.VERSION_17\n }\n}\n')
            import shutil
            shutil.copytree(SOURCE.parents[1] / 'native', root / 'native')
            activity = root / 'android/app/src/main/kotlin/com/pulsemessenger/pulse_messenger/MainActivity.kt'
            activity.parent.mkdir(parents=True)
            activity.write_text('package com.pulsemessenger.pulse_messenger\nimport io.flutter.embedding.android.FlutterActivity\nclass MainActivity: FlutterActivity()\n')
            cmake = root / 'windows/CMakeLists.txt'
            cmake.parent.mkdir(parents=True)
            cmake.write_text('cmake_minimum_required(VERSION 3.14)\nset(BINARY_NAME "pulse_messenger")\n')
            runner = root / 'windows/runner/main.cpp'
            runner.parent.mkdir()
            runner.write_text('window.Create(L"PULSE");')
            resources = runner.parent / 'Runner.rc'
            resources.write_text('VALUE "OriginalFilename", "pulse_messenger.exe"')
            with patch('shutil.which', return_value=r'C:\flutter\bin\flutter.bat'), patch('subprocess.run') as run:
                runpy.run_path(str(script))
                runpy.run_path(str(script))
                self.assertEqual(run.call_args.args[0][0], r'C:\flutter\bin\flutter.bat')
                self.assertTrue(run.call_args.kwargs['cwd'].samefile(root))
            self.assertIn('L"Pulse"', runner.read_text())
            self.assertIn('Pulse.exe', resources.read_text())
            self.assertIn('set(BINARY_NAME "Pulse")', cmake.read_text())
            self.assertEqual(activity.read_text().count('PulseNativeEditor(this,'), 1)
            self.assertEqual(cmake.read_text().count('# Pulse native editor'), 1)
            text = manifest.read_text()
            for permission in ['INTERNET', 'CAMERA', 'RECORD_AUDIO', 'POST_NOTIFICATIONS']:
                self.assertEqual(text.count('android.permission.' + permission), 1)
            self.assertEqual(text.count('android:scheme="https"'), 1)
            self.assertEqual(text.count('firebase_messaging_auto_init_enabled'), 1)
            self.assertEqual(gradle.read_text().count('desugar_jdk_libs'), 1)
            self.assertIn('VERSION_17', gradle.read_text())
            import xml.etree.ElementTree as ET
            for variant in ['values','values-night','values-v31','values-night-v31']:
                tree = ET.parse(root / 'android/app/src/main/res' / variant / 'styles.xml')
                launch = next(x for x in tree.getroot().findall('style') if x.get('name')=='LaunchTheme')
                names = [x.get('name') for x in launch.findall('item')]
                self.assertEqual(names.count('android:windowBackground'),1)
                if 'v31' in variant: self.assertEqual(names.count('android:windowSplashScreenAnimatedIcon'),1)
            self.assertTrue((root / 'android/app/src/main/res/drawable/ic_pulse_notification.xml').is_file())
if __name__ == '__main__':
    unittest.main()
