from pathlib import Path
import shutil
import tempfile
import unittest
import xml.etree.ElementTree as ET

class CallAndroidSetupTest(unittest.TestCase):
    def test_lock_screen_permissions_receiver_and_ringtone_resource(self):
        script = (Path(__file__).resolve().parents[1] / 'scripts/bootstrap.py').read_text()
        setup = script[script.index("manifest = root /"):script.index("icon = root /")]
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            manifest = root / 'android/app/src/main/AndroidManifest.xml'
            manifest.parent.mkdir(parents=True)
            manifest.write_text('<manifest xmlns:android="http://schemas.android.com/apk/res/android"><application><activity android:name=".MainActivity"/></application></manifest>')
            audio = root / 'assets/audio/incoming.ogg'
            audio.parent.mkdir(parents=True)
            audio.write_bytes(b'OggS-fixture')
            exec(compile(setup, 'bootstrap-call-setup', 'exec'), {'root': root, 'shutil': shutil})
            xml = ET.parse(manifest).getroot()
            ns = '{http://schemas.android.com/apk/res/android}'
            permissions = {p.attrib[ns+'name'] for p in xml.findall('uses-permission')}
            self.assertIn('android.permission.USE_FULL_SCREEN_INTENT', permissions)
            activity = xml.find('application/activity')
            self.assertEqual(activity.attrib[ns+'showWhenLocked'], 'true')
            self.assertEqual(activity.attrib[ns+'turnScreenOn'], 'true')
            self.assertEqual(xml.find('application/receiver').attrib[ns+'exported'], 'false')
            self.assertEqual((root / 'android/app/src/main/res/raw/pulse_ringtone.ogg').read_bytes(), audio.read_bytes())
