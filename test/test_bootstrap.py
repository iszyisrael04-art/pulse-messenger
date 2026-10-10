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
            with patch('shutil.which', return_value=r'C:\flutter\bin\flutter.bat'), patch('subprocess.run') as run:
                runpy.run_path(str(script))
                runpy.run_path(str(script))
                self.assertEqual(run.call_args.args[0][0], r'C:\flutter\bin\flutter.bat')
                self.assertTrue(
    run.call_args.kwargs['cwd'].samefile(root)
)
            text = manifest.read_text()
            for permission in ['INTERNET', 'CAMERA', 'RECORD_AUDIO', 'POST_NOTIFICATIONS']:
                self.assertEqual(text.count('android.permission.' + permission), 1)
            self.assertEqual(text.count('android:scheme="https"'), 1)
            self.assertEqual(text.count('firebase_messaging_auto_init_enabled'), 1)
            self.assertEqual(gradle.read_text().count('desugar_jdk_libs'), 1)
            self.assertIn('VERSION_17', gradle.read_text())
            self.assertTrue((root / 'android/app/src/main/res/drawable/ic_pulse_notification.xml').is_file())
if __name__ == '__main__':
    unittest.main()
