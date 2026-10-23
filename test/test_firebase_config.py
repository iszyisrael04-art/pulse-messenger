import json
from pathlib import Path
import sys
import tempfile
import unittest
import xml.etree.ElementTree as ET
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'scripts'))
from configure_firebase import configure

class FirebaseConfigTest(unittest.TestCase):
    def test_native_process_startup_resources_and_secret_rejection(self):
        with tempfile.TemporaryDirectory() as tmp:
            root=Path(tmp)
            config=root/'config.example.json'
            config.write_text(json.dumps({'SUPABASE_URL':'https://fixture.supabase.co','SUPABASE_PUBLISHABLE_KEY':'sb_publishable_fixture_public_key'}))
            values={'FIREBASE_API_KEY':'public<&fixture','FIREBASE_APP_ID':'1:fixture:android:fixture','FIREBASE_MESSAGING_SENDER_ID':'12345','FIREBASE_PROJECT_ID':'pulse-fixture'}
            self.assertTrue(configure(config,json.dumps(values)))
            xml=root/'android/app/src/main/res/values/pulse_firebase.xml'
            resources={node.attrib['name']:node.text for node in ET.parse(xml).getroot()}
            self.assertEqual(resources['google_api_key'],values['FIREBASE_API_KEY'])
            self.assertEqual(resources['google_app_id'],values['FIREBASE_APP_ID'])
            with self.assertRaises(ValueError):configure(config,json.dumps({'private_key':'never-include'}))
            self.assertFalse(configure(config,''))
